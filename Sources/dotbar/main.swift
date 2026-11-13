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
    // A below-bar item temporarily seated next to the separator so its menu opens where it is visible.
    struct Seat { let key: String; let savedValue: Double; let savedLength: CGFloat; var chevron = false }
    var seat: Seat?
    var parkedForCollapse = false   // we expanded Apple's chevron (parked path); collapse it when the interaction ends
    var absentForPush = false       // old absent path drew the hidden icons back; push again when the interaction ends
    var cleanupMonitor: Any?
    var localCleanupMonitor: Any?

    func applicationDidFinishLaunching(_ n: Notification) {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        dot.autosaveName = "dotbar.dot"
        separator.autosaveName = "dotbar.separator"
        spacer.autosaveName = "dotbar.spacer"
        guard let b = dot.button else { return }
        b.target = self
        b.action = #selector(click)
        b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        bar.onPress = { [weak self] it, showMenu in self?.open(it, showMenu: showMenu) }
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

    // The About window, opened from the dot's menu — the same mini page as UsageBar's and NeverSleep's: the app
    // icon at 96 pt, name, "Version x (build y)", © line with the operator's public identity (Marcus1571, not the
    // real name), the license, the GitHub repo and a one-line tagline. An accessory app has no menu bar, so this
    // lives in the dot's right-click menu.
    private var aboutWindow: NSWindow?

    @objc func about() {
        if aboutWindow == nil {
            let info = Bundle.main.infoDictionary ?? [:]
            let v = info["CFBundleShortVersionString"] as? String ?? "?"
            let b = info["CFBundleVersion"] as? String ?? "?"
            func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .labelColor) -> NSTextField {
                let l = NSTextField(labelWithString: s)
                l.font = .systemFont(ofSize: size, weight: weight)
                l.textColor = color
                l.alignment = .center
                return l
            }
            let link = NSTextField(labelWithAttributedString: NSAttributedString(
                string: "github.com/Marcus1571/dotbar",
                attributes: [.link: URL(string: "https://github.com/Marcus1571/dotbar")!,
                             .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.linkColor]))
            link.isSelectable = true
            link.alignment = .center
            let tagline = label("Hide the menu-bar icons you do not need every day and reach them in a second bar below the menu bar.", 11, .regular, .secondaryLabelColor)
            tagline.lineBreakMode = .byWordWrapping
            tagline.preferredMaxLayoutWidth = 252
            let divider = NSBox()
            divider.boxType = .separator
            divider.widthAnchor.constraint(equalToConstant: 260).isActive = true
            let icon = NSImageView(image: NSApp.applicationIconImage)
            icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
            let stack = NSStackView(views: [icon, label("dotbar", 22, .bold),
                                            label("Version \(v) (build \(b))", 11, .regular, .secondaryLabelColor),
                                            divider, label("© 2026 Marcus1571", 13),
                                            label("MIT", 11, .regular, .secondaryLabelColor), link, tagline])
            stack.orientation = .vertical
            stack.spacing = 10
            stack.alignment = .centerX
            stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: stack.fittingSize.height),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "About dotbar"
            w.isReleasedWhenClosed = false
            w.contentView = stack
            aboutWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.center()
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    // The app going away must leave the menu bar as it found it: undo a pending seat (file only — the separator's
    // length and the rest die with the process).
    func applicationWillTerminate(_ n: Notification) {
        guard let s = seat else { return }
        seat = nil
        if var p = layout.read() {
            p[s.key] = s.savedValue
            layout.write(p)
        }
        log("seat: restored on quit (\(s.key))")
    }

    @objc func pickProfile(_ i: NSMenuItem) {
        guard let name = i.representedObject as? String else { return }
        layout.apply(name)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in refresh() }
    }

    @objc func click() {
        guard let e = NSApp.currentEvent else { return }
        if e.type == .rightMouseUp || e.modifierFlags.contains(.option) {
            let m = NSMenu()
            m.addItem(withTitle: "About dotbar", action: #selector(about), keyEquivalent: "")
            m.addItem(.separator())
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
        flushSeat()
        bar.hide()
        guard arranging else { layout.captureCurrent(); refresh(); return }
        expand()
        dot.button?.title = "✓"
        if let f = dot.button?.window?.frame {
            bar.show([], below: f, hint: "Icons left of ┃ leave the menu bar and appear when you click the dot. Hold ⌘ and drag an icon across ┃ to move it. Click ✓ when done.")
        }
    }

    // A below-bar click opens the item's real menu under the item's real position (macOS gives no other choice, see
    // findings.md) — so the icon must be drawn when pressed, and the point is *where* it is drawn for that moment.
    // Drawn: press it where it is. Parked behind Apple's collapsed overflow chevron: expand the chevron (draws it
    // inline), press, collapse when the interaction ends. Absent (pushed by our separator, or dropped by macOS for
    // lack of room — no AX trace at all): briefly seat the item next to the separator (see seatAndPress), press it
    // there, and put it back when the interaction ends. A ghost (off the bar since before this run, no element) gets
    // the same seat when its app has one unambiguous layout key, else just activates the app.
    func open(_ it: Item, showMenu: Bool) {
        flushSeat()   // never two seats at once: put a still-pending one back first
        if it.ghost { seatAndPress(it, showMenu: showMenu, order: 0, requireSingleKey: true); return }
        let now = menuBarItems()
        if let f = now.first(where: { $0.el == it.el })
            ?? now.first(where: { $0.app.processIdentifier == it.app.processIdentifier && !it.title.isEmpty && $0.title == it.title }) {
            if let c = overflowButton(), !c.expanded, f.x < c.x {
                AXUIElementPerformAction(c.el, kAXPressAction as CFString)
                parkedForCollapse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in press(f, showMenu: showMenu, path: "parked") }
            } else {
                press(f, showMenu: showMenu, path: "drawn")
            }
            return
        }
        // Not on the bar: pushed by our separator, or dropped by macOS. The remembered element and the item's order
        // among its app's items (from the scan where they all showed) are what the seat needs.
        let appItems = (known[it.app.processIdentifier] ?? []).sorted { $0.x < $1.x }
        let order = appItems.count > 1 ? (appItems.firstIndex { $0.el == it.el || $0.title == it.title } ?? 0) : 0
        seatAndPress(it, showMenu: showMenu, order: order, requireSingleKey: false)
    }

    // Seat-and-open for an item that is not on the bar. Writes the item's preferred position to just right of the
    // separator in the layout file — MenuBarAgent reorders live, so the item draws there, visible on any display —
    // shrinks the separator by about the item's width so the chain still fits (macOS drops or clamps a too-wide
    // item, and a clamped one leaves no room for the seated icon), waits for the item to appear, presses it there,
    // and restores everything once the interaction ends.
    private func seatAndPress(_ it: Item, showMenu: Bool, order: Int, requireSingleKey: Bool) {
        guard layout.hasAccess, let p = layout.read(), let sepV = p[Layout.separatorKey],
              let key = layout.key(for: it.app, order: order, in: p, requireSingleKey: requireSingleKey),
              let saved = p[key], saved > sepV else {
            log("seat: not possible for \(it.app.localizedName ?? "?") (access=\(layout.hasAccess), key=\(keyDescription(it, order: order)))")
            if it.ghost { it.app.activate(); log("activate ghost \(it.app.localizedName ?? "?")"); return }
            fallbackAbsent(it, showMenu: showMenu)
            return
        }
        let seatValue = sepV - 0.5
        let savedLength = separator.length
        generation += 1   // stop any in-flight grow (e.g. the one restoring a just-flushed seat)
        layout.write(p.merging([key: seatValue]) { _, new in new })
        separator.length = max(narrow, savedLength - max(24, it.w + 8))
        seat = Seat(key: key, savedValue: saved, savedLength: savedLength)
        log("seat: \(key) \(saved) -> \(seatValue), separator \(Int(savedLength)) -> \(Int(separator.length))")
        pressSeated(it, showMenu: showMenu, tries: 2)
    }

    private func keyDescription(_ it: Item, order: Int) -> String {
        let p = layout.read() ?? [:]
        return layout.key(for: it.app, order: order, in: p, requireSingleKey: false) ?? "none"
    }

    // Wait for MenuBarAgent to lay the seated item out, then press it. If it ended up parked after all (packed bar),
    // Apple's chevron still draws it inline. If it never appears, undo the seat and use the old path.
    private func pressSeated(_ it: Item, showMenu: Bool, tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            let now = menuBarItems()
            let fresh = now.first { $0.el == it.el }
                ?? now.first { $0.app.processIdentifier == it.app.processIdentifier && (it.title.isEmpty || $0.title == it.title) }
            guard let f = fresh else {
                if tries > 1 { pressSeated(it, showMenu: showMenu, tries: tries - 1); return }
                log("seat: item did not appear next to the separator; undoing the seat and using the old path")
                if let s = seat { restoreSeat(s) }
                fallbackAbsent(it, showMenu: showMenu)
                return
            }
            if let c = overflowButton(), !c.expanded, f.x < c.x {
                seat?.chevron = true
                AXUIElementPerformAction(c.el, kAXPressAction as CFString)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in pressClicked(f, showMenu: showMenu, path: "seated+chevron") }
            } else {
                pressClicked(f, showMenu: showMenu, path: "seated")
            }
        }
    }

    // A freshly seated item is pressed with a real synthetic click at its drawn position, left or right button per
    // the click: some apps (BetterDisplay) answer a real click but silently ignore the accessibility press on an
    // item that just appeared (measured 2026-11-11: AXPress returned AXError 0 and no menu), and Apple's agents
    // without a real app support neither AXPress nor AXShowMenu. Falls back to the accessibility press if the
    // events cannot be posted.
    private func pressClicked(_ it: Item, showMenu: Bool, path: String) {
        if it.frame != .zero, postClick(it.frame, right: showMenu) {
            log("press \(it.app.localizedName ?? "?") \(it.title.prefix(30)) path=\(path) action=\(showMenu ? "right" : "left") click frame=\(Int(it.frame.minX))..\(Int(it.frame.maxX))")
            armCleanup()
        } else {
            press(it, showMenu: showMenu, path: path)   // logs and arms the cleanup itself
        }
    }

    // Post a real click at a frame in screen coordinates — what a finger would have done.
    private func postClick(_ f: CGRect, right: Bool) -> Bool {
        let p = CGPoint(x: f.midX, y: f.midY)
        let b: CGMouseButton = right ? .right : .left
        guard let down = CGEvent(mouseEventSource: nil, mouseType: right ? .rightMouseDown : .leftMouseDown, mouseCursorPosition: p, mouseButton: b),
              let up = CGEvent(mouseEventSource: nil, mouseType: right ? .rightMouseUp : .leftMouseUp, mouseCursorPosition: p, mouseButton: b)
        else { return false }
        for e in [down, up] { e.setIntegerValueField(.mouseEventClickState, value: 1) }
        down.post(tap: .cghidEventTap)
        usleep(30_000)
        up.post(tap: .cghidEventTap)
        return true
    }

    // Press the item's element: kAXPressAction opens the item's primary menu; a right-click asks for the secondary
    // (context) menu with AXShowMenu, falling back to the press when an item has no such action.
    private func press(_ it: Item, showMenu: Bool, path: String) {
        var err = AXUIElementPerformAction(it.el, showMenu ? "AXShowMenu" as CFString : kAXPressAction as CFString)
        if showMenu, err != .success {
            let first = err
            err = AXUIElementPerformAction(it.el, kAXPressAction as CFString)
            log("AXShowMenu failed (AXError \(first.rawValue)); pressed instead")
        }
        log("press \(it.app.localizedName ?? "?") \(it.title.prefix(30)) path=\(path) action=\(showMenu ? "showMenu" : "press") x=\(Int(it.x)) -> AXError \(err.rawValue)")
        armCleanup()
    }

    // Old path, when the seat is not possible: shrink the separator so the item is drawn again, press the element
    // remembered from when it was visible (some apps keep it working), push again after the interaction ends.
    private func fallbackAbsent(_ it: Item, showMenu: Bool) {
        expand()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            let err = AXUIElementPerformAction(it.el, showMenu ? "AXShowMenu" as CFString : kAXPressAction as CFString)
            log("press \(it.app.localizedName ?? "?") \(it.title.prefix(30)) path=absent action=\(showMenu ? "showMenu" : "press") -> AXError \(err.rawValue)")
            absentForPush = true
            armCleanup()
        }
    }

    // When the interaction ends (the next mouse click anywhere, or Escape/Return — plain keys stay out so the menu
    // can be navigated while the item stays seated): put the seat back, collapse the chevron if we expanded it,
    // push the hidden icons away again if the old path drew them.
    private func armCleanup() {
        if let m = cleanupMonitor { NSEvent.removeMonitor(m); cleanupMonitor = nil }
        if let m = localCleanupMonitor { NSEvent.removeMonitor(m); localCleanupMonitor = nil }
        let fire = { [weak self] in
            guard let self else { return }
            if let m = self.cleanupMonitor { NSEvent.removeMonitor(m); self.cleanupMonitor = nil }
            if let m = self.localCleanupMonitor { NSEvent.removeMonitor(m); self.localCleanupMonitor = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.finishInteraction() }
        }
        let menuEnds = { (e: NSEvent) -> Bool in e.type != .keyDown || e.keyCode == 53 || e.keyCode == 36 || e.keyCode == 76 }
        cleanupMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { e in if menuEnds(e) { fire() } }
        localCleanupMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { e in
            if menuEnds(e) { fire() }
            return e
        }
    }

    private func finishInteraction() {
        let chevron = parkedForCollapse || seat?.chevron == true
        let wasAbsent = absentForPush
        parkedForCollapse = false
        absentForPush = false
        if chevron, let c = overflowButton(), c.expanded { AXUIElementPerformAction(c.el, kAXPressAction as CFString) }
        if let s = seat { restoreSeat(s) } else if wasAbsent, !arranging { collapse() }
    }

    // Put a seated item back where it was (its saved preferred position in the layout file), restore the separator's
    // length and re-tighten the push from there — like refit, not from narrow, so hidden icons do not flash back.
    private func restoreSeat(_ s: Seat) {
        seat = nil
        if var p = layout.read() {
            p[s.key] = s.savedValue
            layout.write(p)
        } else { log("seat: restore failed, the layout file is unreadable") }
        separator.length = s.savedLength
        generation += 1
        if let f = separator.button?.window?.frame { grow(generation, length: separator.length, steps: [16, 4], minX: f.minX) }
        log("seat: restored \(s.key) -> \(s.savedValue), separator -> \(Int(s.savedLength))")
    }

    // Undo a pending seat before anything else moves the bar (another open, a refresh, arranging). restoreSeat also
    // re-tightens the push, which refresh re-does anyway — harmless.
    func flushSeat() {
        guard let s = seat else { return }
        log("seat: flushed before refresh")
        restoreSeat(s)
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
            .map { Item(el: AXUIElementCreateApplication($0.processIdentifier), app: $0, x: 0, w: 0, y: 0, h: 0, title: "", ghost: true) }
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
        flushSeat()
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
        grow(generation, length: narrow, steps: [64, 16, 4], minX: separator.button?.window?.frame.minX ?? 0)
    }

    // With short app menus macOS stops the separator at the hidden icons that still fit left of it and keeps them
    // drawn, and it even draws parked items inline right after the app menus while Accessibility reports them parked
    // behind the chevron (both measured 2026-11-13). The invisible spacer must therefore cover the whole gap from the
    // end of the frontmost app's menus to the separator — that anchor is stable no matter how macOS's transient
    // re-packs move the icons; the icons' own frames are not. macOS re-packs the bar seconds after a length change,
    // so every finished squeeze schedules a settle check.
    func squeeze(_ gen: Int, tries: Int) {
        guard gen == generation, tries > 0, let sep = separator.button?.window?.frame.minX else { return }
        let all = menuBarItems()
        guard !all.isEmpty else { settleCheck(gen); return }
        let drawn = all.filter { $0.x < sep }
        let start = appMenusEnd() ?? drawn.first?.x
        guard let start, sep - start > 1 else {
            log("squeeze: 0 hidden icon(s) drawn left of the separator at x=\(Int(sep)) (\(all.count) items read), spacer \(Int(spacer.length))")
            settleCheck(gen)
            return
        }
        let set = max(1, sep - start - 4)
        if Int(spacer.length) == Int(set), drawn.isEmpty {
            // Already covering the whole gap: parked items have no room to be drawn inline. Done.
            log("squeeze: 0 hidden icon(s) drawn left of the separator at x=\(Int(sep)) (\(all.count) items read), spacer \(Int(spacer.length))")
            settleCheck(gen)
            return
        }
        if Int(spacer.length) == Int(set) {
            spacer.length = max(1, set - 8)   // this exact width changed nothing (macOS dropped it): try thinner
        } else {
            spacer.length = set
        }
        log("squeeze: spacer -> \(Int(spacer.length)) covering x=\(Int(start))..\(Int(sep)), \(drawn.count) hidden icon(s) drawn left of the separator")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in squeeze(gen, tries: tries - 1) }
    }

    // macOS re-packs the bar asynchronously, sometimes seconds after our length change: the grow/squeeze dance can end
    // before the settle, with hidden icons drawn in the final layout. Re-check once it has — a few rounds deep at most,
    // nothing when there is nothing to do, so this is not polling.
    func settleCheck(_ gen: Int, depth: Int = 0) {
        guard depth < 4 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            guard gen == generation, pushed, !arranging, seat == nil, !bar.isShown else { return }
            guard let sep = separator.button?.window?.frame.minX else { return }
            let all = menuBarItems()
            guard !all.isEmpty, all.contains(where: { $0.x < sep }) else { return }
            log("settle: hidden icon(s) drawn after macOS re-packed, squeezing again (round \(depth + 1))")
            squeeze(gen, tries: 5)
        }
    }

    // After an app switch: shrink in 64-point steps while the left edge stays pinned (macOS clamps a too-wide item at the
    // app menus and lets it overflow to the right), then grow as usual. Starting from the current width (not from
    // narrow) keeps hidden icons from flashing back on every switch.
    func refit() {
        guard pushed else { return }
        generation += 1
        spacer.length = 40
        shrink(generation, minX: separator.button?.window?.frame.minX ?? 0)
    }

    func shrink(_ gen: Int, minX: CGFloat) {
        guard gen == generation, let w = separator.button?.window else { return }
        let len = separator.length
        guard len > narrow else { grow(gen, length: len, steps: [64, 16, 4], minX: w.frame.minX); return }
        separator.length = max(narrow, len - 64)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
            guard gen == generation else { return }
            let f = w.frame
            log("shrink \(Int(separator.length)) frame=\(Int(f.minX))..\(Int(f.maxX)) \(f.minX > minX + 1 ? "fits" : "still clamped")")
            if f.minX > minX + 1 { grow(gen, length: separator.length, steps: [64, 16, 4], minX: f.minX) } else { shrink(gen, minX: f.minX) }
        }
    }

    // macOS 27 ignores a status item wider than the room it has (it clamps the left edge at the app menus,
    // and the room depends on the frontmost app), so widen the separator step by step until a step is refused,
    // then back off to the last accepted width and refine with smaller steps.
    // A step is accepted when the left edge moved left by the step. The right edge is no reference: items between the
    // separator and the dot (iStat Menus text) change width all the time and move it.
    func grow(_ gen: Int, length: CGFloat, steps: [CGFloat], minX: CGFloat) {
        guard gen == generation, let w = separator.button?.window else { return }
        guard let step = steps.first else { squeeze(gen, tries: 5); return }
        let next = length + step
        separator.length = next
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
            guard gen == generation else { return }
            let f = w.frame
            let accepted = f.minX <= minX - step + 1
            log("grow \(Int(next)) frame=\(Int(f.minX))..\(Int(f.maxX)) moved=\(Int(minX - f.minX)) \(accepted ? "ok" : "refused")")
            if accepted {
                grow(gen, length: next, steps: steps, minX: f.minX)
            } else {
                separator.length = length
                grow(gen, length: length, steps: Array(steps.dropFirst()), minX: minX)
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
