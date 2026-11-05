# Changelog

## 0.1.0 (unreleased, work in progress)

- Dot + `┃` separator; icons left of the separator are hidden by pushing them away with a wide separator. Because macOS 27 drops items wider than the room it has, the separator grows in steps until macOS refuses (the room depends on the frontmost app).
- Click the dot: a floating bar below the menu bar lists the hidden items (from Accessibility). Click one: the hidden icons return, the real item is pressed, they hide again after the next click.
- Right-click the dot: Arrange icons / Done arranging, Refresh hidden icons, Quit.
- App icons in the bar; text beside the icon for apps with several items; SF Symbols for Apple's menu-extra agents (no real icon).
- Needs Accessibility only. Signed with a local self-signed certificate so the grant survives rebuilds. Logs to `/tmp/dotbar.log`.
- Known: hiding by pushing is unreliable on large displays, and the laptop-only case is untested. See `findings.md`.
- Hidden-item inventory now comes from MenuBarAgent's single Accessibility window (complete on macOS 27, includes items parked behind the overflow arrow).
