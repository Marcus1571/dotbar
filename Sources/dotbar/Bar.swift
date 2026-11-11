import AppKit
import ApplicationServices

// Menu-bar items as seen through Accessibility (no Screen Recording needed).
struct Item {
    let el: AXUIElement
    let app: NSRunningApplication
    let x: CGFloat, w: CGFloat
    let title: String
    var ghost = false   // remembered from an earlier run but not seen since: no element to press yet
}

private func attr(_ el: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success ? v : nil
}

private var agentPID: pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first?.processIdentifier
}

// Apple's own overflow chevron, present only while some items do not fit. Collapsed: "menu-bar-overflow-indicator"
// (items left of it are parked, not drawn); expanded: "menu-bar-overflow-indicator-expanded" (parked items drawn inline).
func overflowButton() -> (el: AXUIElement, x: CGFloat, expanded: Bool)? {
    guard let pid = agentPID, let bar = attr(AXUIElementCreateApplication(pid), "AXExtrasMenuBar") else { return nil }
    for k in (attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
        guard let id = attr(k, "AXIdentifier") as? String, id.hasPrefix("menu-bar-overflow-indicator") else { continue }
        var r = CGRect.zero
        if let f = attr(k, "AXFrame") { AXValueGetValue(f as! AXValue, .cgRect, &r) }
        return (k, r.minX, id.hasSuffix("-expanded"))
    }
    return nil
}

// macOS 27 draws every status item in one MenuBarAgent window. Its AX children are one group per item, the item's own
// element inside (owned by the item's app), and the overflow chevron as a bare button. Unlike each app's AXExtrasMenuBar,
// this also lists items parked behind the overflow chevron.
func menuBarItems() -> [Item] {
    guard let agent = agentPID, let win = (attr(AXUIElementCreateApplication(agent), kAXWindowsAttribute) as? [AXUIElement])?.first
    else { return [] }
    var out: [Item] = []
    for g in (attr(win, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
        // One level only: deeper is an open menu, whose first item ("About This Mac", ...) is not the status item.
        guard let el = (attr(g, kAXChildrenAttribute) as? [AXUIElement])?.first else { continue }
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        guard pid != getpid(), pid != agent, let app = NSRunningApplication(processIdentifier: pid) else { continue }
        var r = CGRect.zero
        if let f = attr(g, "AXFrame") { AXValueGetValue(f as! AXValue, .cgRect, &r) }
        let t = (attr(el, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (attr(el, kAXDescriptionAttribute) as? String) ?? ""
        out.append(Item(el: el, app: app, x: r.minX, w: r.width, title: t))
    }
    return out.sorted { $0.x < $1.x }
}

// The second bar: a small floating strip under the menu bar, one button per hidden item.
final class BarPanel {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private var monitor: Any?
    private var items: [Item] = []
    var isShown: Bool { panel.isVisible }
    var onPress: ((Item, _ showMenu: Bool) -> Void)?
    var onArrange: (() -> Void)?

    init() {
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    // hint: a text-only bar that stays up until hide() (outside clicks are the ⌘-drags it explains).
    func show(_ items: [Item], below anchor: NSRect, hint: String? = nil) {
        hide()
        self.items = items
        let perApp = Dictionary(grouping: items, by: { $0.app.processIdentifier }).mapValues(\.count)
        let stack = NSStackView()
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        for (i, it) in items.enumerated() {
            let b = BarButton()
            b.isBordered = false
            // Apple's menu-extra agents have no real icon (just a generic placeholder), so use a matching SF Symbol.
            let symbols = ["com.apple.KerberosMenuExtra": "key.fill", "com.apple.TextInputMenuAgent": "keyboard"]
            let sym = it.app.bundleIdentifier.flatMap { symbols[$0] }
            let appleAgent = it.app.bundleIdentifier?.hasPrefix("com.apple.") ?? false
            if appleAgent {
                b.imagePosition = .imageOnly
                b.image = NSImage(systemSymbolName: sym ?? "square.grid.2x2", accessibilityDescription: it.app.localizedName)?
                    .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
            } else {
                b.imagePosition = it.title.isEmpty || perApp[it.app.processIdentifier] == 1 ? .imageOnly : .imageLeft
                b.image = it.app.icon.map { $0.resized(20) }
                b.title = b.imagePosition == .imageOnly ? "" : " " + String(it.title.split(separator: "\n").first ?? "").prefix(16)
            }
            b.font = .systemFont(ofSize: 11)
            b.toolTip = "\(it.app.localizedName ?? "") \(it.title)".trimmingCharacters(in: .whitespaces)
            if it.ghost {
                b.alphaValue = 0.4
                b.toolTip = "\(it.app.localizedName ?? "") is off the screen and dotbar has not seen its icon since it started. Make room once (plug in a display, or switch to an app with short menus) and it becomes clickable."
            }
            b.tag = i
            b.target = self
            b.action = #selector(press(_:))
            stack.addArrangedSubview(b)
        }
        let fx = NSVisualEffectView()
        fx.material = .menu; fx.state = .active; fx.wantsLayer = true
        fx.layer?.cornerRadius = 10; fx.layer?.masksToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor), stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            stack.topAnchor.constraint(equalTo: fx.topAnchor), stack.bottomAnchor.constraint(equalTo: fx.bottomAnchor)])
        if let hint {
            let l = NSTextField(labelWithString: hint)
            l.font = .systemFont(ofSize: 12)
            stack.addArrangedSubview(l)
        } else {
            if items.isEmpty {
                let l = NSTextField(labelWithString: "No hidden icons")
                l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor
                stack.addArrangedSubview(l)
            }
            let a = NSButton(image: NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Arrange icons")!,
                             target: self, action: #selector(arrange))
            a.isBordered = false
            a.contentTintColor = .secondaryLabelColor
            a.toolTip = "Choose which icons live here"
            stack.addArrangedSubview(a)
        }
        panel.contentView = fx
        let size = stack.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main!
        let x = min(max(anchor.maxX - size.width, screen.frame.minX + 4), screen.frame.maxX - size.width - 4)
        panel.setFrame(NSRect(x: x, y: anchor.minY - 4 - size.height, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        guard hint == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hide() }
    }

    func hide() {
        panel.orderOut(nil)
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    @objc private func arrange() {
        hide()
        onArrange?()
    }

    @objc private func press(_ b: NSButton) {
        let it = items[b.tag]
        hide()
        onPress?(it, NSApp.currentEvent?.type == .rightMouseDown)
    }
}

// NSButton ignores right clicks; the below-bar buttons want them, so a right-click opens the item's context menu.
final class BarButton: NSButton {
    override func rightMouseDown(with event: NSEvent) {
        if let t = target, let a = action { NSApp.sendAction(a, to: t, from: self) }
    }
}

extension NSImage {
    func resized(_ s: CGFloat) -> NSImage {
        let r = NSImage(size: NSSize(width: s, height: s))
        r.lockFocus(); draw(in: NSRect(x: 0, y: 0, width: s, height: s)); r.unlockFocus()
        return r
    }
}
