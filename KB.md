# dotbar knowledge base

How dotbar actually works. The pitch is in [README.md](README.md); research and measurements are in [findings.md](findings.md).

## Menu bar items
dotbar owns two status items, created in this order because macOS places newer items to the left of older ones:
- **The dot** (`•`, `◦` while expanded): left-click toggles the bar below the menu bar; right-click or Option-click opens dotbar's menu.
- **The separator** (`┃` while arranging, empty otherwise): icons to its left are the hidden ones.

## Hiding (pushing)
`collapse()` widens the separator so the items on its left are pushed toward the app menus, where macOS 27 parks them behind its overflow arrow when there is no room. macOS drops a status item wider than its room, so `grow()` widens in steps of 64, 16 and 4 points, checks each step ~80 ms later (frames update asynchronously) and keeps the last accepted width. `expand()` shrinks the separator back to 14 points. A `generation` counter stops a stale `grow()`. Why this is unreliable: [findings.md](findings.md#macos-27-menu-bar-measured-through-accessibility-2026-11-05).

## Inventory
`menuBarItems()` (`Sources/dotbar/Bar.swift`) walks the one AX window of `com.apple.MenuBarAgent`: one group per item, the owner's element inside. It skips dotbar's own items and Apple's MenuBarAgent-owned items (clock, battery, Wi-Fi, sound, Control Center). `overflowButton()` finds Apple's « chevron and whether it is expanded.

`scan()` is the cheap re-read (nothing moves). The bar lists:
- items whose centre is left of the separator (hidden by you);
- items left of the collapsed chevron (parked by macOS);
- **off-bar** items: seen earlier in this run (kept in `known` with their element) and gone from the bar while their app still runs, i.e. dropped by macOS for lack of room ([why](findings.md#laptop-screen-alone-notch-measured-2026-11-05));
- **ghosts**: apps whose icon was off the bar in an earlier run (bundle ids in the `offbar` user default) and not seen since. Shown dimmed with a tooltip; clicking activates the app, since there is no element to press until the icon has been seen once.

An empty read (menu bar off screen) is ignored. Scans run on the dot click, on app launch (after 3 s) and quit; `refresh()` (shrink the separator, wait 0.4 s, scan, push again) runs at start, on display changes and from the menu. No polling.

## The bar below the menu bar
`BarPanel` is a borderless non-activating `NSPanel` at status-bar level, on all Spaces, right-aligned under the dot. One button per hidden item: the app icon; a short text label when an app has several items; SF Symbols for Apple agents without an icon (`KerberosMenuExtra` → `key.fill`, `TextInputMenuAgent` → `keyboard`, other `com.apple.*` → `square.grid.2x2`). The last button (`slider.horizontal.3`) starts arranging. Any click outside closes it.

## Arranging
Started from the bar's slider button or the menu. Shrinks the separator (hidden icons come back, `┃` shows), the dot shows `✓`, and a text-only bar under the dot explains the ⌘-drag and stays up (no outside-click monitor, since the drags are outside clicks). Clicking `✓` (or *Done arranging*) closes the hint and runs `refresh()`, which re-reads positions and pushes again. Which icons are hidden is purely their position left of `┃`; on the laptop screen alone the separator itself is dropped, so arrange with a larger display attached.

## Opening an item
The menu always opens under the item's real position in the menu bar (macOS gives no other choice, see [findings.md](findings.md#why-the-other-menu-bar-managers-broke-on-macos-27-read-2026-11-05)), so `open()` first makes sure it is drawn, by path:
- **drawn**: `AXPress` at once;
- **parked** (left of the collapsed chevron): press the chevron, wait 0.5 s, press the item (drawn inline left of the notch), collapse the chevron 0.4 s after the next click or key;
- **absent** (pushed by the separator, or dropped): shrink the separator, wait 0.5 s, press the remembered element, push again after the next click or key.

## dotbar's menu
Arrange icons… / Done arranging (shows `┃` so you can ⌘-drag icons across it), Refresh hidden icons (re-reads the inventory), Launch at login (checkmark = registered with `SMAppService.mainApp`, i.e. the copy in `~/Applications`; result in the log), Quit dotbar.

## Permissions
Accessibility only (macOS 27: Privacy & Security → *Device Control and Data Access*). Prompted on first launch. No Screen Recording, no network.

## Build
`scripts/build-app.sh` compiles `Sources/dotbar/*.swift` with plain `swiftc -O` (no SwiftPM, no Xcode), target macOS 14, into `build/dotbar.app` (bundle id `local.dotbar`, `LSUIElement`). `--install` copies it to `~/Applications`, kills the running copy and launches the new one.

## Signing
The script signs with the login-keychain identity **"dotbar local signing"** if present (override with `SIGN_IDENTITY`), else ad hoc. A stable certificate keeps the Accessibility grant across rebuilds: the designated requirement is `identifier "local.dotbar" and certificate leaf = H"15089f59..."`. The certificate was made with `openssl` and imported with `security import` (EKU codeSigning); `find-identity` shows `CSSMERR_TP_NOT_TRUSTED`, but codesign accepts it. It is never in the repo; if the keychain is lost, create a new one and re-grant. With an ad-hoc build: `tccutil reset Accessibility local.dotbar`, relaunch, re-grant.

## Debug log
`/tmp/dotbar.log`, append-only, reset past 1 MB, every line timestamped. Each scan logs its trigger, item count, separator x, chevron x, then every item as `HIDDEN`/`shown`, plus `OFFBAR` and `GHOST` lines. Each press logs app, title, path, x, chevron state and the `AXError` code.
