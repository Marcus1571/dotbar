import AppKit
import ApplicationServices
import ServiceManagement

// Menu-bar hider with a second bar: icons left of the separator are pushed away; click the dot to see them
// in a small bar below the menu bar and click one to open it. Needs only Accessibility (no Screen Recording).
let narrow: CGFloat = 14

final class App: NSObject, NSApplicationDelegate {
    // Created dot first, separator second: macOS places newer items to the LEFT of older ones.
    let dot = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let separator = NSStatusBar.system.statusItem(withLength: narrow)
    let bar = BarPanel()
    var hidden: [Item] = []
    var known: [Item] = []   // every item seen while its app runs: macOS 27 drops items with no room and they leave no AX trace
    var arranging = false
    var generation = 0   // bumped on every layout change so a stale grow() stops

    func applicationDidFinishLaunching(_ n: Notification) {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        dot.autosaveName = "dotbar.dot"
        separator.autosaveName = "dotbar.separator"
        guard let b = dot.button else { return }
        b.target = self
        b.action = #selector(click)
        b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        bar.onPress = { [weak self] in self?.open($0) }
        // Rescan when the room changes or an app may have added an item; no polling.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.scan("app launched") }
        }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.scan("app quit") }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refresh() }
        }
        refresh()
    }

    @objc func click() {
        guard let e = NSApp.currentEvent else { return }
        if e.type == .rightMouseUp || e.modifierFlags.contains(.option) {
            let m = NSMenu()
            m.addItem(withTitle: arranging ? "Done arranging" : "Arrange icons…", action: #selector(toggleArranging), keyEquivalent: "")
            m.addItem(withTitle: "Refresh hidden icons", action: #selector(refreshAction), keyEquivalent: "")
            m.addItem(.separator())
            m.addItem(withTitle: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "").state =
                SMAppService.mainApp.status == .enabled ? .on : .off
            m.addItem(withTitle: "Quit dotbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            dot.menu = m; dot.button?.performClick(nil); dot.menu = nil
        } else if bar.isShown {
            bar.hide()
        } else if let f = dot.button?.window?.frame {
            scan("dot")
            bar.show(hidden, below: f)
        }
    }

    @objc func refreshAction() { refresh() }

    // Registers the installed app as a login item (System Settings > General > Login Items).
    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        do { try s.status == .enabled ? s.unregister() : s.register(); log("login item: \(s.status.rawValue)") }
        catch { log("login item failed: \(error)") }
    }

    @objc func toggleArranging() {
        arranging.toggle()
        if arranging { expand() } else { refresh() }
    }

    // An app opens its menu under its icon's real position, so the icon must be drawn when pressed. Drawn: press it.
    // Parked behind Apple's overflow chevron: expand the chevron (draws it inline), press, collapse after the next click.
    // Not on the bar (pushed by our separator, or dropped by macOS for lack of room): shrink the separator and press
    // the element remembered from when it was visible; some apps still open that way.
    func open(_ it: Item) {
        if it.ghost { it.app.activate(); log("activate ghost \(it.app.localizedName ?? "?")"); return }
        let now = menuBarItems()
        let present = now.contains { $0.el == it.el }
        let chevron = overflowButton()
        let path = !present ? "absent" : chevron.map { !$0.expanded && it.x < $0.x } == true ? "parked" : "drawn"
        if path == "parked", let c = chevron { AXUIElementPerformAction(c.el, kAXPressAction as CFString) }
        if path == "absent" { expand() }
        DispatchQueue.main.asyncAfter(deadline: .now() + (path == "drawn" ? 0 : 0.5)) { [self] in
            let err = AXUIElementPerformAction(it.el, kAXPressAction as CFString)
            log("press \(it.app.localizedName ?? "?") \(it.title.prefix(30)) path=\(path) x=\(Int(it.x)) chevron=\(chevron.map { "\(Int($0.x))\($0.expanded ? " expanded" : "")" } ?? "none") -> AXError \(err.rawValue)")
            var m: Any?
            m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
                if let mm = m { NSEvent.removeMonitor(mm) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if path == "parked", let c = overflowButton(), c.expanded { AXUIElementPerformAction(c.el, kAXPressAction as CFString) }
                    if path == "absent", self?.arranging == false { self?.collapse() }
                }
            }
        }
    }

    // Cheap re-read without moving anything: remember every item, and list as hidden the ones left of our separator,
    // the ones parked behind the chevron, and remembered ones whose app runs but that are no longer on the bar.
    func scan(_ why: String) {
        let all = menuBarItems()
        // An empty read means the menu bar is not on screen (full screen, display asleep): keep the last good state.
        guard !all.isEmpty else { log("scan (\(why)) skipped: menu bar not readable"); return }
        known.removeAll { k in k.app.isTerminated || all.contains { $0.el == k.el } }
        let gone = known
        known += all
        let sep = separator.button?.window?.frame.minX ?? 0
        let chevron = overflowButton().flatMap { $0.expanded ? nil : $0.x }
        // Apps whose icon was off the bar in an earlier run and is still not seen: listed dimmed, so nothing vanishes silently.
        let seen = Set((all + gone).compactMap(\.app.bundleIdentifier))
        let ghosts = (UserDefaults.standard.stringArray(forKey: "offbar") ?? []).filter { !seen.contains($0) }
            .compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
            .map { Item(el: AXUIElementCreateApplication($0.processIdentifier), app: $0, x: 0, w: 0, title: "", ghost: true) }
        UserDefaults.standard.set(Array(Set((gone + ghosts).compactMap(\.app.bundleIdentifier))).sorted(), forKey: "offbar")
        hidden = all.filter { i in i.x + i.w / 2 < sep || chevron.map { i.x < $0 } == true } + gone + ghosts
        log("scan (\(why)) items=\(all.count) sepMinX=\(Int(sep)) chevron=\(chevron.map { "\(Int($0))" } ?? "none") hidden=\(hidden.count) offbar=\(gone.count)\n"
            + all.map { i in "  \(hidden.contains { $0.el == i.el } ? "HIDDEN" : "shown ") x=\(Int(i.x)) \(i.app.localizedName ?? "?") \(i.title.prefix(30))" }.joined(separator: "\n")
            + gone.map { "\n  OFFBAR \($0.app.localizedName ?? "?") \($0.title.prefix(30))" }.joined()
            + ghosts.map { "\n  GHOST  \($0.app.localizedName ?? "?") (off the bar, not seen since launch)" }.joined())
    }

    func expand() {
        generation += 1
        dot.button?.title = "◦"
        separator.button?.title = "┃"
        separator.length = narrow
    }

    // Expand, read where every item sits (expanded, our hidden items are back on the bar when there is room), then
    // push them away again.
    func refresh() {
        expand()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            guard !arranging else { return }
            log("refresh trusted=\(AXIsProcessTrusted())")
            scan("refresh")
            collapse()
        }
    }

    func collapse() {
        generation += 1
        dot.button?.title = "•"
        separator.button?.title = ""
        grow(generation, length: narrow, steps: [64, 16, 4], right: separator.button?.window?.frame.maxX ?? 0)
    }

    // macOS 27 ignores a status item wider than the room it has (it clamps the left edge at the app menus,
    // and the room depends on the frontmost app), so widen the separator step by step until a step is refused,
    // then back off to the last accepted width and refine with smaller steps.
    func grow(_ gen: Int, length: CGFloat, steps: [CGFloat], right: CGFloat) {
        guard gen == generation, let step = steps.first, let w = separator.button?.window else { return }
        let next = length + step
        separator.length = next
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
            guard gen == generation else { return }
            let f = w.frame
            let accepted = abs(f.maxX - right) < 1 && abs(f.minX - (right - next - 3)) < 1
            if accepted {
                grow(gen, length: next, steps: steps, right: right)
            } else {
                separator.length = length
                grow(gen, length: length, steps: Array(steps.dropFirst()), right: right)
            }
        }
    }
}

// Append-only debug log, reset when it passes 1 MB.
func log(_ s: String) {
    let path = "/tmp/dotbar.log"
    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    if size > 1_000_000 { try? FileManager.default.removeItem(atPath: path) }
    if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
    guard let h = FileHandle(forWritingAtPath: path) else { return }
    h.seekToEndOfFile()
    h.write(Data("\(Date().formatted(date: .omitted, time: .standard)) \(s)\n".utf8))
    h.closeFile()
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
