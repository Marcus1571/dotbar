import AppKit

// Menu-bar hider: icons left of the separator collapse off-screen when you click the dot.
// No permissions, no polling: the only work is flipping one status item's length on click.
let autoCollapseSeconds: TimeInterval = 10   // 0 = never auto-collapse

final class App: NSObject, NSApplicationDelegate {
    // Created dot first, separator second: macOS places newer items to the LEFT of older ones.
    let dot = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let separator = NSStatusBar.system.statusItem(withLength: 14)
    var collapsed = false
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        dot.autosaveName = "dotbar.dot"
        separator.autosaveName = "dotbar.separator"
        guard let b = dot.button else { return }
        b.target = self
        b.action = #selector(click)
        b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        separator.button?.target = self   // clicking the pipe toggles too, and keeps it full-contrast
        separator.button?.action = #selector(click)
        set(collapsed: false)
    }

    @objc func click() {
        guard let e = NSApp.currentEvent else { return }
        if e.type == .rightMouseUp || e.modifierFlags.contains(.option) {
            let m = NSMenu()
            m.addItem(withTitle: "Quit dotbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            dot.menu = m; dot.button?.performClick(nil); dot.menu = nil
        } else {
            set(collapsed: !collapsed)
        }
    }

    func set(collapsed c: Bool) {
        // macOS 27 ignores an item wider than the room it has (verified: 800 px pushes icons off, 1200 px is dropped),
        // so size the separator to reach just the screen's left edge, measured while it is still narrow.
        var length: CGFloat = 14
        if c, !collapsed, let w = separator.button?.window {
            length = max(14, w.frame.maxX - (w.screen?.frame.minX ?? 0) - 4)
        }
        collapsed = c
        separator.length = length
        separator.button?.title = c ? "" : "┃"
        dot.button?.title = c ? "•" : "◦"
        timer?.invalidate()
        if !c && autoCollapseSeconds > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: autoCollapseSeconds, repeats: false) { [weak self] _ in
                self?.set(collapsed: true)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
