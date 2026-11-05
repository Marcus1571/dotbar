# Status (2026-11-05)

## Where things stand
Version 0.1.0, unreleased. Works: dot and separator in the menu bar, the bar below the menu bar listing hidden items, pressing one opens its real menu, Accessibility only, ~0% CPU idle.

Not good enough (the operator's own words, 2026-11-05): the bar's icons are "unusable". Clicking one brings all hidden icons back into the main bar and opens the menu up there, which does nothing for the real problem: on the laptop screen alone there is no room, so the icon would not even show. Hiding by pushing is also unreliable (it depends on the frontmost app's menus, see [findings.md](findings.md)).

## Hard constraint (settled by research 2026-11-05)
No tool can open another app's menu or popover under dotbar's bar: the app anchors it to its own icon's position in the real menu bar, and the icon must be drawn there when pressed. Thaw 3 and Bartender live with the same limit. The design choice is therefore *where* the clicked icon is drawn for that moment. Evidence: [findings.md](findings.md#why-the-other-menu-bar-managers-broke-on-macos-27-read-2026-11-05).

## In flight
- 2026-11-05: inventory switched to MenuBarAgent's AX window (complete, includes parked items).
- **Next and blocking: the laptop-alone test.** The operator opens the lid, unplugs the external display and tells the agent; the agent then measures from the terminal whether MenuBarAgent shows its overflow arrow, where hidden items are parked, and where the inline expansion draws them next to the notch.

## Candidate designs (decided after the laptop test)
1. **Seat beside the dot:** on click, move only that icon next to the dot (⌘-drag while it is drawn, or a write to the menu-bar order file after a one-time file pick), press it so its menu opens right above the bar, move it back after the menu closes. Closest to "in place". Risk: ⌘-drag moves the pointer, which is what made Bartender 6 feel broken.
2. **Use Apple's overflow:** the dot presses macOS's own overflow arrow, so the hidden icons are drawn inline in the real menu bar (over the app menus) and work natively. Simplest and most robust, but it is not a bar below.
3. Later regardless of design: user-chosen hidden list (bundle id + title in `UserDefaults`), auto-refresh on `NSWorkspace` launch/terminate notifications, launch at login (`SMAppService`), profiles, icon limit.
