# dotbar

A tiny macOS menu-bar manager: icons you do not need every day move out of the way, and a **second bar below the menu bar** lists them; click one to open it. Native Swift/AppKit, one process, about 0% CPU, no Screen Recording, no network, no dependencies.

Built because Bartender 6 stopped working on macOS 27 (see [docs/FINDINGS.md](docs/FINDINGS.md)). **Status: work in progress**, working but rough.

## How it works
- The menu bar has two items of ours: a dot (the button) and a `┃` separator. Icons to the **left of the separator** are the hidden ones.
- Click the dot: a small bar appears under the menu bar with those icons (app icons; live text for apps that expose it). Click an icon: the hidden icons come back, the real item is pressed (its menu opens in its normal place), and everything hides again after your next click.
- Right-click (or Option-click) the dot: **Arrange icons…** shows the `┃` so you can Cmd+drag it next to the dot (icons left of it are the hidden ones), **Done arranging**, **Refresh hidden icons** (after apps start or quit), **Quit dotbar**.

## Permissions
**Accessibility** only (to list and press other apps' menu bar items). On macOS 27 it is called *Device Control and Data Access*: System Settings → Privacy & Security. The first launch asks for it. dotbar is signed with a stable local certificate so the grant survives rebuilds; see below.

## Build
`scripts/build-app.sh --install` builds `build/dotbar.app`, copies it to `~/Applications` and launches it. Plain `swiftc` (SwiftPM is not used). It signs with the keychain certificate "dotbar local signing" if present, else ad hoc (then macOS forgets the Accessibility grant on every rebuild: `tccutil reset Accessibility local.dotbar` and re-grant).

## Files
- `Sources/dotbar/main.swift`: status items, separator sizing (`grow`), refresh/collapse/expand, press flow.
- `Sources/dotbar/Bar.swift`: Accessibility item listing (`menuBarItems`) and the floating bar (`BarPanel`).
- `docs/FINDINGS.md`: everything learned about macOS 27, and the open questions. **Read this first.**

## Roadmap
Test on a laptop without an external display (rely on macOS's own overflow), user-chosen hidden list, auto-refresh, launch at login, icon limit, profiles. Details in `docs/FINDINGS.md`.
