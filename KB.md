# dotbar knowledge base

How dotbar actually works. The pitch is in [README.md](README.md); research and measurements are in [findings.md](findings.md).

## Menu bar items
dotbar owns two status items, created in this order because macOS places newer items to the left of older ones:
- **The dot** (`•`, `◦` while expanded): left-click toggles the bar below the menu bar; right-click or Option-click opens dotbar's menu.
- **The separator** (`┃` while arranging, empty otherwise): icons to its left are the hidden ones.

## Hiding (pushing)
`collapse()` widens the separator so the items on its left are pushed toward the app menus, where macOS 27 parks them behind its overflow arrow when there is no room. macOS drops a status item wider than its room, so `grow()` widens in steps of 64, 16 and 4 points, checks each step ~80 ms later (frames update asynchronously) and keeps the last accepted width. A step is accepted when the separator's **left** edge moved left by the step; when refused, macOS pins the left edge at the app menus and lets the item overflow to the right. The right edge is no reference: icons between the separator and the dot change width (iStat Menus text) and move it. `expand()` shrinks the separator back to 14 points. A `generation` counter stops a stale `grow()`. Every `grow` step is logged (`grow <length> frame=<minX>..<maxX> ok|refused`).

The room changes with the frontmost app, so on every app activation `refit()` (only while pushed) shrinks in 64-point steps while the left edge stays pinned (logged `shrink … still clamped|fits`), then grows as usual; starting from the current width keeps hidden icons from flashing back.

An invisible third item, the **spacer** (`dotbar.spacer`), sits just left of the separator (its position is written to the layout file at launch, separator + 1, when access is granted): 40 points while pushed (reset on every re-fit), 1 while expanded. When a push ends, `squeeze()` reads the bar: if hidden icons are still drawn left of the separator, it widens the spacer by the distance from the leftmost one to the separator, capped at 400 points, and checks again (up to 3 times, each logged as `squeeze:`). Without it, with short app menus macOS keeps the one icon that fits between the app menus and the separator ([measured](findings.md#short-app-menus-leave-hidden-icons-visible-measured-2026-11-05)). Why this is unreliable: [findings.md](findings.md#macos-27-menu-bar-measured-through-accessibility-2026-11-05).

## Inventory
`menuBarItems()` (`Sources/dotbar/Bar.swift`) walks the one AX window of `com.apple.MenuBarAgent`: one group per item, the owner's element as its first child (read one level only: while a menu is open, deeper levels are that menu, e.g. "About This Mac"). It skips dotbar's own items and Apple's MenuBarAgent-owned items (clock, battery, Wi-Fi, sound, Control Center). `overflowButton()` finds Apple's « chevron and whether it is expanded.

`scan()` is the cheap re-read (nothing moves). The bar lists:
- items whose centre is left of the separator (hidden by you);
- items left of the collapsed chevron (parked by macOS);
- **off-bar** items: dropped by macOS for lack of room while their app still runs. `known` keeps, per app, its items from the scan where it showed the most; when an app now shows fewer, that many remembered items (preferring ones whose element is no longer live) are listed. Counted, not matched, because third-party items have no `AXIdentifier` and their element changes whenever the app redraws (iStat Menus does constantly) ([why](findings.md#laptop-screen-alone-notch-measured-2026-11-05));
- **ghosts**: apps whose icon was off the bar in an earlier run (bundle ids in the `offbar` user default) and not seen since. Shown dimmed with a tooltip; clicking activates the app, since there is no element to press until the icon has been seen once.

An empty read (menu bar off screen) is ignored. Scans run on the dot click, on app launch (after 3 s) and quit; `refresh()` (shrink the separator, wait 0.4 s, scan, push again) runs at start, on display changes and from the menu. No polling.

## The bar below the menu bar
`BarPanel` is a borderless non-activating `NSPanel` at status-bar level, on all Spaces, right-aligned under the dot. One button per hidden item: the app icon; a short text label when an app has several items; SF Symbols for Apple agents without an icon (`KerberosMenuExtra` → `key.fill`, `TextInputMenuAgent` → `keyboard`, other `com.apple.*` → `square.grid.2x2`). `BarButton` (an `NSButton` subclass) also answers right-clicks, which AppKit ignores by default. The last button (`slider.horizontal.3`) starts arranging. Any click outside closes it.

## Arranging
Started from the bar's slider button or the menu. Shrinks the separator (hidden icons come back, `┃` shows), the dot shows `✓`, and a text-only bar under the dot explains the ⌘-drag and stays up (no outside-click monitor, since the drags are outside clicks). Clicking `✓` (or *Done arranging*) closes the hint and runs `refresh()`, which re-reads positions and pushes again. Which icons are hidden is purely their position left of `┃`; on the laptop screen alone the separator itself is dropped, so arrange with a larger display attached.

## Opening an item
A below-bar click — left **or** right — opens the item's real menu under the item's real position in the menu bar (macOS gives no other choice, see [findings.md](findings.md#why-the-other-menu-bar-managers-broke-on-macos-27-read-2026-11-05)), so `open()` first makes sure the item is drawn, by path:
- **drawn**: press at once. A left-click presses (`AXPress`, the item's primary menu); a right-click asks for the item's secondary/context menu with `AXShowMenu`, falling back to `AXPress` when the item has no such action.
- **parked** (left of the collapsed chevron): press the chevron, wait 0.5 s, press the item (drawn inline left of the notch), collapse the chevron when the interaction ends.
- **absent** (pushed by the separator, or dropped by macOS for lack of room — no AX trace at all): **seat** it next to the separator for the moment of the press. `seatAndPress()` writes the item's preferred position to `separator value − 0.5` in the layout file (MenuBarAgent reorders live), shrinks the separator's length by about one icon's width (`max(24, item width + 8)`) so the wider chain still fits instead of being clamped at the app menus, waits 0.5 s (one retry) for the item to appear at the seat, finds its fresh element (by element, else by app + title) and presses it there. If the seat itself was parked again, the chevron still draws it inline. When the item never appears, the seat is undone and the old path runs: shrink the separator, press the remembered element, push again after the interaction ends.
- **ghost** (no element, not seen this run): the same seat, but only when its app has exactly one layout key — its order among its app's items is unknown, so multi-item apps fall back to just activating the app.
- **Restore.** The interaction ends on the next mouse click anywhere (a local monitor covers dotbar's own bar and dot, which a global monitor cannot see), or on Escape/Return/Enter — plain keys are excluded so an open menu can still be navigated while the item stays seated. `restoreSeat()` writes the saved position back, restores the separator's length and re-tightens the push from its current width (refit-style, not from narrow, so hidden icons do not flash back). Only one seat at a time: opening another item, a refresh, or arranging first restores a pending one (flushing also stops the in-flight re-tighten by bumping `generation`), and the app restores a pending seat on quit.

Which layout key belongs to an item: every `status:` key whose owner part (before `::`) is the app's bundle id or localized name, minus dotbar's own keys. One match is unambiguous; when an app has several (iStat Menus runs six), the item's left-to-right order among its app's items on the scan where they all showed picks the key, since the file's value order is the menu-bar order.

## dotbar's menu
Arrange icons… / Done arranging (shows `┃` so you can ⌘-drag icons across it), Refresh hidden icons (re-reads the inventory), Settings… (see above), Launch at login (checkmark = registered with `SMAppService.mainApp`, i.e. the copy in `~/Applications`; result in the log), Quit dotbar.

## Layout file and profiles
macOS 27 keeps the menu-bar order in `~/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist`, key `TrailingItemPreferredPositions`: item key → distance from the right edge (`module:Clock` is 0; larger is further left). Keys are `status:<bundle id or app name>::<autosave name>` (`Item-0` when the app gave none) or `module:<Apple module>`. dotbar's separator is `status:dotbar::dotbar.separator`, so "hidden" is simply "larger than the separator's value". Only the order matters to dotbar; it writes positions 0, 30, 60… in list order.

The container refuses reads until the user picks the file in an open panel (Settings › Grant Access); dotbar stores a security-scoped bookmark, and the grant persists across launches. `Layout` (`Sources/dotbar/Layout.swift`) reads the file and writes through `CFPreferencesSetValue` with the absolute-path domain, falling back to a direct file write; the log says which one took (`layout write:`).

Two profiles, **Large display** and **Laptop screen**. The current one (user default `profile`) is picked in the dot's right-click menu (applied at once) or by Settings › Save and Apply; when the display setup changes (any non-built-in display attached, `CGDisplayIsBuiltin`, means Large display; remembered in `profileDisplay`) dotbar switches to the matching one, so a hand-picked profile survives restarts until the displays change. Writing an order reorders the icons on screen live (verified 2026-11-05). A profile is a saved copy of the dictionary (user default `profiles`). It is saved when you click ✓ after ⌘-drag arranging (the current order becomes the active profile) or with Settings › Save and Apply. Applying merges it over the current file, so items it does not know keep their place.

## Settings window
Right-click the dot › Settings… (⌘,); the two profiles are also listed at the top of that menu. Access status with a plain explanation and Grant Access; a segmented control for the two profiles (the active one is marked "In use now"); the profile as a list, drag to reorder, top next to the clock, the `┃` row splitting menu bar (above) from dotbar's bar (below); dimmed rows are apps not running. *Take from the menu bar* reloads the list from the current order; *Save and Apply* saves the profile and, if it is the active one, writes it and rescans.

## Permissions
Accessibility (macOS 27: Privacy & Security → *Device Control and Data Access*), prompted on first launch. Optional: the layout file, granted by picking it (see above). No Screen Recording, no Full Disk Access, no network.

## Build
`scripts/build-app.sh` compiles `Sources/dotbar/*.swift` with plain `swiftc -O` (no SwiftPM, no Xcode), target macOS 14, into `build/dotbar.app` (bundle id `local.dotbar`, `LSUIElement`). `--install` copies it to `~/Applications`, kills the running copy and launches the new one.

## Signing
The script signs with the login-keychain identity **"dotbar local signing"** if present (override with `SIGN_IDENTITY`), else ad hoc. A stable certificate keeps the Accessibility grant across rebuilds: the designated requirement is `identifier "local.dotbar" and certificate leaf = H"15089f59..."`. The certificate was made with `openssl` and imported with `security import` (EKU codeSigning); `find-identity` shows `CSSMERR_TP_NOT_TRUSTED`, but codesign accepts it. It is never in the repo; if the keychain is lost, create a new one and re-grant. With an ad-hoc build: `tccutil reset Accessibility local.dotbar`, relaunch, re-grant.

## Debug log
`/tmp/dotbar.log`, append-only, reset past 1 MB, every line timestamped. Each scan logs its trigger, item count, separator x, chevron x, then every item as `HIDDEN`/`shown`, plus `OFFBAR` and `GHOST` lines. Each press logs app, title, path, x, chevron state and the `AXError` code.
