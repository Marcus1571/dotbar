import AppKit

// Menu-bar hider: icons left of the separator collapse off-screen when you click the dot.
// No permissions, no polling: the only work is flipping one status item's length on click.
let autoCollapseSeconds: TimeInterval = 10   // 0 = never auto-collapse
let hiddenLength: CGFloat = 10_000           // wide enough to push everything on its left off-screen

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
        set(collapsed: UserDefaults.standard.bool(forKey: "collapsed"))
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
        collapsed = c
        UserDefaults.standard.set(c, forKey: "collapsed")
        separator.length = c ? hiddenLength : 14
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
