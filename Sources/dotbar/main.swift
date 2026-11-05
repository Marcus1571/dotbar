import AppKit

// Menu-bar hider: icons left of the separator collapse off-screen when you click the dot.
// No permissions, no polling: the only work is resizing one status item on click.
let autoCollapseSeconds: TimeInterval = 10   // 0 = never auto-collapse
let narrow: CGFloat = 14

final class App: NSObject, NSApplicationDelegate {
    // Created dot first, separator second: macOS places newer items to the LEFT of older ones.
    let dot = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let separator = NSStatusBar.system.statusItem(withLength: narrow)
    var collapsed = false
    var timer: Timer?
    var generation = 0   // bumped on every toggle so a stale grow() stops

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
        collapsed = c
        generation += 1
        timer?.invalidate()
        dot.button?.title = c ? "•" : "◦"
        separator.button?.title = c ? "" : "┃"
        if c {
            grow(generation, length: narrow, steps: [64, 16, 4], right: separator.button?.window?.frame.maxX ?? 0)
        } else {
            separator.length = narrow
            if autoCollapseSeconds > 0 {
                timer = Timer.scheduledTimer(withTimeInterval: autoCollapseSeconds, repeats: false) { [weak self] _ in
                    self?.set(collapsed: true)
                }
            }
        }
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

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
