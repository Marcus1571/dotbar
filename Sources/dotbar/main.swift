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
    // Invisible, just left of the separator: when an app's menus are short, macOS keeps the one item next to the
    // pushed separator on screen; this makes that survivor ours instead of a hidden icon.
    let spacer = NSStatusBar.system.statusItem(withLength: 1)
    let bar = BarPanel()
    let layout = Layout()
    lazy var settings = SettingsWindow(layout: layout)
    var hidden: [Item] = []
    // Per running app, its items from the scan where it showed the most. macOS 27 drops items with no room and they
    // leave no AX trace; an app's item elements also change when it redraws, so drops are counted, not matched.
    var known: [pid_t: [Item]] = [:]
    var arranging = false
    var generation = 0   // bumped on every layout change so a stale grow() stops
    var pushed = false   // collapsed: the separator is pushing; false while expanded (arranging, or an item is open)
    var sepRight: CGFloat = 0   // the separator's right edge, fixed by the dot

    func applicationDidFinishLaunching(_ n: Notification) {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        dot.autosaveName = "dotbar.dot"
        separator.autosaveName = "dotbar.separator"
        spacer.autosaveName = "dotbar.spacer"
        guard let b = dot.button else { return }
        b.target = self
        b.action = #selector(click)
        b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        bar.onPress = { [weak self] in self?.open($0) }
        bar.onArrange = { [weak self] in self?.toggleArranging() }
        settings.onApplied = { [weak self] in DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refresh() } }
        // Rescan when the room changes or an app may have added an item; no polling.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.scan("app launched") }
        }
        // The room depends on the frontmost app's menus (findings.md), so a width fitted for one app is wrong for the next.
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.refit() }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.scan("app quit") }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.layout.applyForDisplay(); self?.refresh() }
        }
        log("launch: layout access=\(layout.hasAccess) profile=\(layout.current) display=\(Layout.displayProfile) saved=\(Layout.profileNames.filter { layout.profile($0) != nil })")
        layout.applyForDisplay()
        layout.placeSpacer()
        refresh()
    }

    @objc func openSettings() { settings.show() }

    @objc func pickProfile(_ i: NSMenuItem) {
        guard let name = i.representedObject as? String else { return }
        layout.apply(name)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in refresh() }
    }

    @objc func click() {
        guard let e = NSApp.currentEvent else { return }
        if e.type == .rightMouseUp || e.modifierFlags.contains(.option) {
            let m = NSMenu()
            if layout.hasAccess {
                for name in Layout.profileNames {
                    let i = m.addItem(withTitle: name, action: #selector(pickProfile(_:)), keyEquivalent: "")
                    i.state = name == layout.current ? .on : .off
                    i.representedObject = name
                }
                m.addItem(.separator())
            }
            m.addItem(withTitle: arranging ? "Done arranging" : "Arrange icons…", action: #selector(toggleArranging), keyEquivalent: "")
            m.addItem(withTitle: "Refresh hidden icons", action: #selector(refreshAction), keyEquivalent: "")
            m.addItem(.separator())
            m.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            m.addItem(withTitle: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "").state =
                SMAppService.mainApp.status == .enabled ? .on : .off
            m.addItem(withTitle: "Quit dotbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            dot.menu = m; dot.button?.performClick(nil); dot.menu = nil
        } else if arranging {
            toggleArranging()
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
        bar.hide()
        guard arranging else { layout.captureCurrent(); refresh(); return }
        expand()
        dot.button?.title = "✓"
        if let f = dot.button?.window?.frame {
            bar.show([], below: f, hint: "Icons left of ┃ leave the menu bar and appear when you click the dot. Hold ⌘ and drag an icon across ┃ to move it. Click ✓ when done.")
        }
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
        known = known.filter { !($0.value.first?.app.isTerminated ?? true) }
        let now = Dictionary(grouping: all, by: \.app.processIdentifier)
        for (pid, items) in now where items.count >= known[pid]?.count ?? 0 { known[pid] = items }
        var gone: [Item] = []
        for (pid, items) in known {
            let live = now[pid] ?? []
            guard live.count < items.count else { continue }
            // ponytail: picks remembered items without a live match; may pick the wrong one when a redraw and a drop coincide.
            gone += items.filter { k in !live.contains { $0.el == k.el } }.prefix(items.count - live.count)
        }
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
        pushed = false
        spacer.length = 1
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
        pushed = true
        spacer.length = 40
        dot.button?.title = "•"
        separator.button?.title = ""
        sepRight = separator.button?.window?.frame.maxX ?? 0
        grow(generation, length: narrow, steps: [64, 16, 4], right: sepRight)
    }

    // With short app menus macOS stops the separator at the hidden icons that still fit left of it and keeps them drawn
    // (findings.md). Widen the invisible spacer over them so they no longer fit, then check again.
    func squeeze(_ gen: Int, tries: Int) {
        guard gen == generation, tries > 0, let sep = separator.button?.window?.frame.minX else { return }
        let all = menuBarItems(), left = all.filter { $0.x < sep }
        guard let first = left.first else { log("squeeze: nothing drawn left of the separator at x=\(Int(sep)) (\(all.count) items read)"); return }
        spacer.length += sep - first.x
        log("squeeze: \(left.count) hidden icon(s) still drawn from x=\(Int(first.x)) to the separator at x=\(Int(sep)), spacer -> \(Int(spacer.length))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in squeeze(gen, tries: tries - 1) }
    }

    // After an app switch: shrink in 64-point steps while macOS refuses the width, then grow as usual. Starting from
    // the current width (not from narrow) keeps hidden icons from flashing back on every switch.
    func refit() {
        guard pushed else { return }
        generation += 1
        spacer.length = 40
        shrink(generation)
    }

    func shrink(_ gen: Int) {
        guard gen == generation, let w = separator.button?.window else { return }
        let len = separator.length
        if len <= narrow || abs(w.frame.minX - (sepRight - len - 3)) < 1 && abs(w.frame.maxX - sepRight) < 1 {
            grow(gen, length: len, steps: [64, 16, 4], right: sepRight)
            return
        }
        separator.length = max(narrow, len - 64)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in shrink(gen) }
    }

    // macOS 27 ignores a status item wider than the room it has (it clamps the left edge at the app menus,
    // and the room depends on the frontmost app), so widen the separator step by step until a step is refused,
    // then back off to the last accepted width and refine with smaller steps.
    func grow(_ gen: Int, length: CGFloat, steps: [CGFloat], right: CGFloat) {
        guard gen == generation, let w = separator.button?.window else { return }
        guard let step = steps.first else { squeeze(gen, tries: 3); return }
        let next = length + step
        separator.length = next
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
            guard gen == generation else { return }
            let f = w.frame
            let accepted = abs(f.maxX - right) < 1 && abs(f.minX - (right - next - 3)) < 1
            log("grow \(Int(next)) frame=\(Int(f.minX))..\(Int(f.maxX)) right=\(Int(right)) \(accepted ? "ok" : "refused")")
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
