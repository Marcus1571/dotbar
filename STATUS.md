# Status (2026-11-11)

## Where things stand
Version 0.2.0, released 2026-11-11. Works: dot and separator in the menu bar, the bar below the menu bar listing hidden items, pressing one opens its real menu, Accessibility only, ~0% CPU idle.

New in this session (unreleased): **seated opening** — clicking (left *or* right) a below-bar icon that is not drawn seats it just right of the separator for the moment of the press (a layout-file write; MenuBarAgent reorders live), so its menu opens next to the separator where it is visible on any display, and the item returns to its hidden order when the interaction ends. This is the fix for dropped icons ("not represented, ever, no matter where you click"): even an item with no Accessibility trace gets pressed, via its layout key. Right-click asks the item for its context menu (`AXShowMenu`). Design and evidence: [findings.md](findings.md#seating-a-clicked-item-next-to-the-separator-2026-11-11), behaviour: [KB.md](KB.md#opening-an-item).

## Hard constraint (settled by research 2026-11-05)
No tool can open another app's menu or popover under dotbar's bar: the app anchors it to its own icon's position in the real menu bar, and the icon must be drawn there when pressed. Thaw 3 and Bartender live with the same limit. The design choice is therefore *where* the clicked icon is drawn for that moment — the seat answers it: next to the separator, briefly. Evidence: [findings.md](findings.md#why-the-other-menu-bar-managers-broke-on-macos-27-read-2026-11-05).

## In flight
- **To verify by the operator (2026-11-11, build installed):** click a below-bar icon — its menu should open with the icon visible just right of the separator, and the icon should go back when the menu closes (`seat:` + `press … path=seated` in `/tmp/dotbar.log`). Also try a right-click (context menu where the app has one) and a dimmed ghost (single-item app only).
- 2026-11-05: laptop-alone test done (operator's screenshots + AX reads, see [findings.md](findings.md#laptop-screen-alone-notch-measured-2026-11-05)). Result: macOS parks what does not fit behind its « chevron and **drops** what does not fit even there, with no AX trace. The operator's call: dotbar is worth it exactly for those, so the bar must list escaped icons automatically.
- Profiles built 2026-11-05 (Settings window, auto-switch). Writes go through cfprefsd, and MenuBarAgent honoured a new item's written position. Writing an order reorders icons on screen live (verified: the Large display profile's order is what the menu bar shows). Unverified: whether a *dropped* item re-appears live when written to a good position — the seat's own premise; the operator click above answers it.

## Known limits
- An icon macOS drops before dotbar ever saw it in this run cannot be pressed; it shows dimmed (if remembered) until there is room once — except single-item-app ghosts, which the seat now makes clickable.
- On the laptop dotbar's own separator is dropped too (it sits leftmost), so the hand-picked hidden list only takes effect while there is room.
- A packed laptop bar may displace the leftmost visible icon into the chevron while a seat is open; it comes back on restore.

## Later
Icon limit: the seat now covers single-item apps; multi-item apps whose key order is ambiguous (iStat Menus) fall back to the old path when absent.
