import AppKit
import ApplicationServices

// Menu-bar items as seen through Accessibility (no Screen Recording needed).
struct Item {
    let el: AXUIElement
    let app: NSRunningApplication
    let x: CGFloat, w: CGFloat
    let title: String
}

private func attr(_ el: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success ? v : nil
}

func menuBarItems() -> [Item] {
    var out: [Item] = []
    for app in NSWorkspace.shared.runningApplications
    where app.processIdentifier != getpid() && app.bundleIdentifier != "com.apple.MenuBarAgent" {
        guard let bar = attr(AXUIElementCreateApplication(app.processIdentifier), "AXExtrasMenuBar") else { continue }
        for k in (attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            var pt = CGPoint.zero, sz = CGSize.zero
            if let p = attr(k, kAXPositionAttribute) { AXValueGetValue(p as! AXValue, .cgPoint, &pt) }
            if let s = attr(k, kAXSizeAttribute) { AXValueGetValue(s as! AXValue, .cgSize, &sz) }
            let t = (attr(k, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (attr(k, kAXDescriptionAttribute) as? String) ?? ""
            out.append(Item(el: k, app: app, x: pt.x, w: sz.width, title: t))
        }
    }
    return out.sorted { $0.x < $1.x }
}

// The second bar: a small floating strip under the menu bar, one button per hidden item.
final class BarPanel {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private var monitor: Any?
    private var items: [Item] = []
    var isShown: Bool { panel.isVisible }
    var onPress: ((Item) -> Void)?

    init() {
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(_ items: [Item], below anchor: NSRect) {
        self.items = items
        let perApp = Dictionary(grouping: items, by: { $0.app.processIdentifier }).mapValues(\.count)
        let stack = NSStackView()
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        for (i, it) in items.enumerated() {
            let b = NSButton()
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
        if items.isEmpty {
            let l = NSTextField(labelWithString: "No hidden icons")
            l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor
            stack.addArrangedSubview(l)
        }
        panel.contentView = fx
        let size = stack.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main!
        let x = min(max(anchor.maxX - size.width, screen.frame.minX + 4), screen.frame.maxX - size.width - 4)
        panel.setFrame(NSRect(x: x, y: anchor.minY - 4 - size.height, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hide() }
    }

    func hide() {
        panel.orderOut(nil)
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    @objc private func press(_ b: NSButton) {
        let it = items[b.tag]
        hide()
        onPress?(it)
    }
}

extension NSImage {
    func resized(_ s: CGFloat) -> NSImage {
        let r = NSImage(size: NSSize(width: s, height: s))
        r.lockFocus(); draw(in: NSRect(x: 0, y: 0, width: s, height: s)); r.unlockFocus()
        return r
    }
}
