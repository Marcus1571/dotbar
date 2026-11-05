import AppKit

// macOS 27 keeps the menu-bar order in one preferences file in MenuBarAgent's group container: a dictionary
// "TrailingItemPreferredPositions" from item key ("status:<bundle id or app name>::<autosave name>", "module:Clock", ...)
// to a distance from the right edge (0 = the clock). The container refuses every read until the user picks the file in
// an open panel (the panel runs in a system process and hands the access back); a security-scoped bookmark keeps it.
final class Layout {
    static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist")
    static let key = "TrailingItemPreferredPositions"
    static let separatorKey = "status:dotbar::dotbar.separator"
    private var scoped: URL?

    init() {
        guard let b = UserDefaults.standard.data(forKey: "layoutBookmark") else { return }
        var stale = false
        if let u = try? URL(resolvingBookmarkData: b, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
           u.startAccessingSecurityScopedResource() {
            scoped = u
            if stale { remember(u) }
        }
    }

    var hasAccess: Bool { read() != nil }

    // Returns whether the user picked the layout file.
    func requestAccess() -> Bool {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = false
        p.directoryURL = Self.file.deletingLastPathComponent()
        p.message = "Select “com.apple.MenuBar.plist” (it is already in view) and click Grant Access. dotbar gets access to this one file only."
        p.prompt = "Grant Access"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let u = p.url, u.standardizedFileURL.path == Self.file.standardizedFileURL.path else {
            log("layout access: not granted (panel closed without com.apple.MenuBar.plist)")
            return false
        }
        _ = u.startAccessingSecurityScopedResource()
        scoped = u
        remember(u)
        log("layout access: granted, readable=\(hasAccess)")
        return hasAccess
    }

    private func remember(_ u: URL) {
        if let b = try? u.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(b, forKey: "layoutBookmark")
        }
    }

    func read() -> [String: Double]? {
        guard let d = try? Data(contentsOf: Self.file),
              let p = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { return nil }
        return (p[Self.key] as? [String: Any])?.compactMapValues { ($0 as? NSNumber)?.doubleValue } ?? [:]
    }

    // Writes through cfprefsd (absolute-path domain) so MenuBarAgent's cached copy is updated, then checks the file.
    // ponytail: falls back to a plain file write, which cfprefsd may not notice; the log says which one took.
    func write(_ positions: [String: Double]) {
        let domain = Self.file.deletingPathExtension().path as CFString
        CFPreferencesSetValue(Self.key as CFString, positions as CFDictionary, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let synced = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        if read() == positions { log("layout write: cfprefsd ok (\(positions.count) items)"); return }
        guard let d = try? Data(contentsOf: Self.file),
              var p = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else {
            log("layout write: failed, cfprefsd sync=\(synced), file unreadable"); return
        }
        p[Self.key] = positions
        do {
            try PropertyListSerialization.data(fromPropertyList: p, format: .binary, options: 0).write(to: Self.file)
            log("layout write: cfprefsd sync=\(synced) did not reach the file; wrote the file directly, now matches=\(read() == positions)")
        } catch { log("layout write: failed, cfprefsd sync=\(synced), file write \(error)") }
    }

    // Two profiles, picked by what is attached: any display that is not the built-in one means "large".
    static var activeProfile: String {
        NSScreen.screens.contains { s in
            (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDisplayIsBuiltin($0.uint32Value) == 0 } ?? false
        } ? "Large display" : "Laptop screen"
    }
    static let profileNames = ["Large display", "Laptop screen"]

    func profile(_ name: String) -> [String: Double]? {
        (UserDefaults.standard.dictionary(forKey: "profiles")?[name] as? [String: Any])?.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }

    func save(_ positions: [String: Double], as name: String) {
        var all = UserDefaults.standard.dictionary(forKey: "profiles") ?? [:]
        all[name] = positions
        UserDefaults.standard.set(all, forKey: "profiles")
        log("profile \(name): saved \(positions.count) items")
    }

    // The arrangement just made by ⌘-drag becomes the active profile.
    func captureActive() {
        guard let now = read() else { return }
        save(now, as: Self.activeProfile)
    }

    private var lastApplied: String?
    // On display changes: put the active profile's order in place, once per switch.
    func applyActive() {
        let name = Self.activeProfile
        guard name != lastApplied, let p = profile(name), let now = read() else { return }
        lastApplied = name
        guard p != now else { return }
        log("profile \(name): applying")
        write(now.merging(p) { _, new in new })
    }
}

// Display names for layout keys.
func layoutLabel(_ key: String) -> (name: String, icon: NSImage?, running: Bool) {
    if key == Layout.separatorKey { return ("┃  above: menu bar · below: dotbar's bar", nil, true) }
    if key.hasPrefix("module:") {
        let m = String(key.dropFirst(7))
        let symbols = ["Clock": "clock", "Battery": "battery.100", "WiFi": "wifi", "Sound": "speaker.wave.2",
                       "NowPlaying": "play.circle", "AudioVideoModule": "video", "BentoBox-0": "switch.2"]
        return (m == "BentoBox-0" ? "Control Center" : m, NSImage(systemSymbolName: symbols[m] ?? "apple.logo", accessibilityDescription: m), true)
    }
    let body = key.hasPrefix("status:") ? String(key.dropFirst(7)) : key
    let parts = body.components(separatedBy: "::")
    let owner = parts.first ?? body, item = parts.count > 1 ? parts[1] : ""
    let app = NSRunningApplication.runningApplications(withBundleIdentifier: owner).first
        ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == owner }
    let url = app?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: owner)
    var name = app?.localizedName ?? url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? owner
    // Multi-item apps name their items (iStat Menus: com.bjango.istatmenus.cpu); "Item-0" style names say nothing.
    if !item.hasPrefix("Item-"), !item.isEmpty, item != owner, owner != "dotbar" { name += " — " + (item.components(separatedBy: ".").last ?? item) }
    if owner == "dotbar" { name = "dotbar •" }
    let icon = app?.icon ?? url.map { NSWorkspace.shared.icon(forFile: $0.path) }
    return (name, icon, app != nil)
}

// Settings: layout access, then each profile as a reorderable list (top = next to the clock).
final class SettingsWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let layout: Layout
    private var window: NSWindow?
    private var rows: [String] = []
    private var keep: [String: Double] = [:]   // the profile's values, kept for keys not shown
    private var profileName = Layout.activeProfile
    private let table = NSTableView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let grant = NSButton(title: "Grant Access…", target: nil, action: nil)
    private let picker = NSSegmentedControl(labels: Layout.profileNames, trackingMode: .selectOne, target: nil, action: nil)
    private let note = NSTextField(wrappingLabelWithString: "")
    var onApplied: (() -> Void)?

    init(layout: Layout) { self.layout = layout }

    func show() {
        if window == nil { build() }
        profileName = Layout.activeProfile
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "dotbar Settings"
        w.isReleasedWhenClosed = false
        w.center()

        let accessTitle = NSTextField(labelWithString: "Menu bar layout")
        accessTitle.font = .boldSystemFont(ofSize: 13)
        grant.target = self; grant.action = #selector(grantAccess)

        let profTitle = NSTextField(labelWithString: "Profiles")
        profTitle.font = .boldSystemFont(ofSize: 13)
        picker.target = self; picker.action = #selector(pick)
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)

        let col = NSTableColumn(identifier: .init("item"))
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 24
        table.dataSource = self; table.delegate = self
        table.registerForDraggedTypes([.string])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let fromBar = NSButton(title: "Take from the menu bar", target: self, action: #selector(takeCurrent))
        let apply = NSButton(title: "Save and Apply", target: self, action: #selector(saveApply))
        apply.keyEquivalent = "\r"
        let buttons = NSStackView(views: [fromBar, NSView(), apply])

        let stack = NSStackView(views: [accessTitle, status, grant, profTitle, picker, note, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.setCustomSpacing(18, after: grant)
        for v in [status, note, scroll, buttons] { v.translatesAutoresizingMaskIntoConstraints = false }
        w.contentView = stack
        NSLayoutConstraint.activate([
            status.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32)])
        col.width = 420
        window = w
    }

    private func reload() {
        let access = layout.hasAccess
        status.stringValue = access
            ? "✓ dotbar can read and rearrange the menu bar order, so each profile can have its own."
            : "macOS keeps the order of the menu bar icons in one protected file. To give each display its own arrangement, dotbar needs to read and change that file. Click Grant Access, select the file “com.apple.MenuBar.plist” that is already in view, and confirm. dotbar gets access to that one file only."
        grant.isHidden = access
        picker.isEnabled = access
        table.isEnabled = access
        picker.selectedSegment = Layout.profileNames.firstIndex(of: profileName) ?? 0
        let saved = layout.profile(profileName) != nil
        note.stringValue = (profileName == Layout.activeProfile ? "In use now. " : "Used when \(profileName == "Large display" ? "an external display is attached" : "only the laptop screen is on"). ")
            + "Drag rows to reorder: top is next to the clock; everything below ┃ goes to dotbar's bar. "
            + (saved ? "" : "Not saved yet: showing the current menu bar.")
        keep = layout.profile(profileName) ?? layout.read() ?? [:]
        rows = keep.keys.filter { !$0.hasPrefix("status:dotbar-dbg") }.sorted { keep[$0]! < keep[$1]! }
        table.reloadData()
    }

    @objc private func grantAccess() { _ = layout.requestAccess(); reload() }

    @objc private func pick() {
        profileName = Layout.profileNames[picker.selectedSegment]
        reload()
    }

    @objc private func takeCurrent() {
        guard let now = layout.read() else { return }
        keep = now
        rows = now.keys.filter { !$0.hasPrefix("status:dotbar-dbg") }.sorted { now[$0]! < now[$1]! }
        table.reloadData()
    }

    // New positions follow the list order; Apple's spacing does not matter, only the order.
    @objc private func saveApply() {
        var p = keep
        for (i, k) in rows.enumerated() { p[k] = Double(i * 30) }
        layout.save(p, as: profileName)
        if profileName == Layout.activeProfile, let now = layout.read() {
            layout.write(now.merging(p) { _, new in new })
            onApplied?()
        }
        reload()
    }

    func numberOfRows(in t: NSTableView) -> Int { rows.count }

    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let l = layoutLabel(rows[row])
        let text = NSTextField(labelWithString: l.name)
        text.lineBreakMode = .byTruncatingTail
        if rows[row] == Layout.separatorKey { text.font = .boldSystemFont(ofSize: 12); text.textColor = .controlAccentColor }
        else if !l.running { text.textColor = .tertiaryLabelColor }
        let img = NSImageView(image: l.icon?.resized(16) ?? NSImage())
        img.widthAnchor.constraint(equalToConstant: 16).isActive = true
        return NSStackView(views: [img, text])
    }

    func tableView(_ t: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let i = NSPasteboardItem()
        i.setString(String(row), forType: .string)
        return i
    }

    func tableView(_ t: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        op == .above ? .move : []
    }

    func tableView(_ t: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let s = info.draggingPasteboard.string(forType: .string), let from = Int(s) else { return false }
        let k = rows.remove(at: from)
        rows.insert(k, at: from < row ? row - 1 : row)
        t.reloadData()
        return true
    }
}
