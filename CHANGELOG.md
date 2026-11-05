# Changelog

## Unreleased

- Profiles in the dot's right-click menu: pick *Large display* or *Laptop screen* and it is applied at once (checkmark on the current one). Plugging or unplugging a display still switches automatically.
- Fix: Save and Apply for the profile not matching the attached display only saved it; it now applies it.

## 0.1.0 (2026-11-05)

- Dot + `┃` separator; icons left of the separator are hidden by pushing them away with a wide separator. Because macOS 27 drops items wider than the room it has, the separator grows in steps until macOS refuses (the room depends on the frontmost app).
- Click the dot: a floating bar below the menu bar lists the hidden items (from Accessibility). Click one: the hidden icons return, the real item is pressed, they hide again after the next click.
- Right-click the dot: Arrange icons / Done arranging, Refresh hidden icons, Quit.
- App icons in the bar; text beside the icon for apps with several items; SF Symbols for Apple's menu-extra agents (no real icon).
- Needs Accessibility only. Signed with a local self-signed certificate so the grant survives rebuilds. Logs to `/tmp/dotbar.log`.
- Known: hiding by pushing is unreliable on large displays, and the laptop-only case is untested. See `findings.md`.
- Hidden-item inventory now comes from MenuBarAgent's single Accessibility window (complete on macOS 27, includes items parked behind the overflow arrow).
- Icons that macOS drops for lack of room (the laptop screen) stay in the bar: dotbar remembers every icon it has seen while its app runs, and remembers across restarts which apps are off the bar (shown dimmed until seen again).
- Clicking an icon in the bar picks the way that opens it: press directly when drawn, expand Apple's overflow chevron when parked behind it, or shrink the separator and press the remembered element.
- Right-click the dot › Launch at login: registers the installed app as a login item (`SMAppService`, listed in System Settings › General › Login Items).
- Arranging is reachable from the bar (slider button at its end); while arranging the dot shows ✓ and a hint under it explains the ⌘-drag until you click ✓.
- Fix: the bar filled with duplicates and "About This Mac" entries (redrawn items were taken for dropped ones; a scan during an open menu read the menu). Drops are now counted per app.
- Profiles: *Large display* and *Laptop screen*, switched automatically. Each is a saved menu-bar order written to macOS's layout file (granted once by picking it). Settings window (⌘,) with a plain explanation, the grant button and a drag-to-reorder list per profile.
- Fix: with an app with short menus in front (e.g. Herdr) hidden icons stayed visible. The push is re-fitted on every app switch, and an invisible spacer takes the last slot macOS keeps.
- Rescans on display changes, app launch/quit and every dot click; append-only timestamped log.
