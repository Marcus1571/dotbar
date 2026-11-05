# Status (2026-11-05)

## Where things stand
Version 0.1.2, released 2026-11-05. Works: dot and separator in the menu bar, the bar below the menu bar listing hidden items, pressing one opens its real menu, Accessibility only, ~0% CPU idle.

Not good enough (the operator's own words, 2026-11-05): the bar's icons are "unusable". Clicking one brings all hidden icons back into the main bar and opens the menu up there, which does nothing for the real problem: on the laptop screen alone there is no room, so the icon would not even show. Hiding by pushing is also unreliable (it depends on the frontmost app's menus, see [findings.md](findings.md)).

## Hard constraint (settled by research 2026-11-05)
No tool can open another app's menu or popover under dotbar's bar: the app anchors it to its own icon's position in the real menu bar, and the icon must be drawn there when pressed. Thaw 3 and Bartender live with the same limit. The design choice is therefore *where* the clicked icon is drawn for that moment. Evidence: [findings.md](findings.md#why-the-other-menu-bar-managers-broke-on-macos-27-read-2026-11-05).

## In flight
- 2026-11-05: laptop-alone test done (operator's screenshots + AX reads, see [findings.md](findings.md#laptop-screen-alone-notch-measured-2026-11-05)). Result: macOS parks what does not fit behind its « chevron and **drops** what does not fit even there, with no AX trace. The operator's call: dotbar is worth it exactly for those, so the bar must list escaped icons automatically.
- Built the same day: memory of every seen item, three press paths (drawn / parked / absent), persisted off-bar list with dimmed ghosts.
- **To verify by the operator:** (1) plug in the external display once, unplug, open the bar: the icons that were dropped should be listed and open on click; plain-menu items like Kerberos are the open question. (2) Click an icon parked behind «: the chevron should expand and its menu open left of the notch.

- Profiles built 2026-11-05 (Settings window, auto-switch). Writes go through cfprefsd, and MenuBarAgent honoured a new item's written position. Writing an order reorders icons on screen live (verified: the Large display profile's order is what the menu bar shows).

## Known limits
- An icon macOS drops before dotbar ever saw it in this run cannot be pressed; it shows dimmed (if remembered) until there is room once.
- On the laptop dotbar's own separator is dropped too (it sits leftmost), so the hand-picked hidden list only takes effect while there is room.

## Later
Icon limit. "Seat beside the dot" (move the clicked icon next to the dot) is shelved: a dropped icon cannot be dragged.
