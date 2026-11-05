# dotbar knowledge base

How dotbar actually works. The pitch is in [README.md](README.md); research and measurements are in [findings.md](findings.md).

## Menu bar items
dotbar owns two status items, created in this order because macOS places newer items to the left of older ones:
- **The dot** (`•`, `◦` while expanded): left-click toggles the bar below the menu bar; right-click or Option-click opens dotbar's menu.
- **The separator** (`┃` while arranging, empty otherwise): icons to its left are the hidden ones.

## Hiding (pushing)
`collapse()` widens the separator so the items on its left are pushed toward the app menus, where macOS 27 parks them behind its overflow arrow when there is no room. macOS drops a status item wider than its room, so `grow()` widens in steps of 64, 16 and 4 points, checks each step ~80 ms later (frames update asynchronously) and keeps the last accepted width. `expand()` shrinks the separator back to 14 points. A `generation` counter stops a stale `grow()`. Why this is unreliable: [findings.md](findings.md#macos-27-menu-bar-measured-through-accessibility-2026-11-05).

## Inventory
`menuBarItems()` (`Sources/dotbar/Bar.swift`) walks the one AX window of `com.apple.MenuBarAgent`: one group per item, the owner's element inside. It skips dotbar's own items and Apple's MenuBarAgent-owned items (clock, battery, Wi-Fi, sound, Control Center). `refresh()` expands, waits 0.4 s, marks every item whose centre is left of the separator as hidden, logs, and collapses again.

## The bar below the menu bar
`BarPanel` is a borderless non-activating `NSPanel` at status-bar level, on all Spaces, right-aligned under the dot. One button per hidden item: the app icon; a short text label when an app has several items; SF Symbols for Apple agents without an icon (`KerberosMenuExtra` → `key.fill`, `TextInputMenuAgent` → `keyboard`, other `com.apple.*` → `square.grid.2x2`). Any click outside closes it.

## Opening an item
`open()` expands (all hidden icons come back), waits 0.5 s, `AXPress`es the item's element, and collapses again 0.4 s after the next mouse or key event anywhere. The menu opens under the item's real position in the menu bar (macOS gives no other choice, see [findings.md](findings.md#why-the-other-menu-bar-managers-broke-on-macos-27-read-2026-11-05)).

## dotbar's menu
Arrange icons… / Done arranging (shows `┃` so you can ⌘-drag icons across it), Refresh hidden icons (re-reads the inventory), Quit dotbar.

## Permissions
Accessibility only (macOS 27: Privacy & Security → *Device Control and Data Access*). Prompted on first launch. No Screen Recording, no network.

## Build
`scripts/build-app.sh` compiles `Sources/dotbar/*.swift` with plain `swiftc -O` (no SwiftPM, no Xcode), target macOS 14, into `build/dotbar.app` (bundle id `local.dotbar`, `LSUIElement`). `--install` copies it to `~/Applications`, kills the running copy and launches the new one.

## Signing
The script signs with the login-keychain identity **"dotbar local signing"** if present (override with `SIGN_IDENTITY`), else ad hoc. A stable certificate keeps the Accessibility grant across rebuilds: the designated requirement is `identifier "local.dotbar" and certificate leaf = H"15089f59..."`. The certificate was made with `openssl` and imported with `security import` (EKU codeSigning); `find-identity` shows `CSSMERR_TP_NOT_TRUSTED`, but codesign accepts it. It is never in the repo; if the keychain is lost, create a new one and re-grant. With an ad-hoc build: `tccutil reset Accessibility local.dotbar`, relaunch, re-grant.

## Debug log
`/tmp/dotbar.log` is rewritten on every refresh (trusted flag, separator x, every item marked `HIDDEN` or `shown`); each press appends a line with its `AXError` code.
