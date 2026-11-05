# Findings (macOS 27.2 "Golden Gate", build 26B123)

Research log: what was measured or read, with verdicts. Current state and next steps live in [STATUS.md](STATUS.md); how dotbar works lives in [KB.md](KB.md).

Measured on a MacBook Air 15" M3 (notch), Swift 6.4.2 with Command Line Tools only (no Xcode; plain `swiftc`). External display: 4K scaled to 1920x1080 points. Treat numbers as examples; the point is the behaviour.

## Why the other menu-bar managers broke on macOS 27 (read 2026-11-05)
- **The cause:** until macOS 26 every status item was its own small window, and every manager (Bartender, Ice, Hidden Bar, Barbee, Thaw 2) found and moved those windows. On macOS 27 Apple's `MenuBarAgent` draws all of them into one shared window, so there is nothing per item to find or move. Everything broke on developer beta 1 (June 2026). Apple also added its own overflow arrow (see below). There is still no public API to manage other apps' items. Sources: [publicspace.net](https://www.publicspace.net/blog/macos-27-menu-bar/), [devsreviews](https://devsreviews.com/reviews/macos-27-menu-bar-managers/), [usetuck vendor status](https://usetuck.com/macos-27-menu-bar-app-compatibility/) (secondhand articles; the Thaw source below is first-hand).
- **Bartender:** 6 is the macOS 26 version (and misbehaves there too: cursor hijacking, ghost clicks, constant reindexing, per [9to5Mac](https://9to5mac.com/2026/01/27/a-decade-with-bartender-showed-me-how-overdue-this-macos-feature-is/) and [heise](https://www.heise.de/en/news/macOS-26-Lag-and-other-issues-with-menu-bar-tool-Bartender-6-11167978.html)). Bartender 7 is the macOS 27 build, paid. On this Mac, Bartender 6.5.0 showed Screen Recording as missing although `tccd` logs `authValue=2 authReason=4` (allowed) and `replayd` re-checks it every ~15 s; resetting and re-granting changed nothing; it idled at ~175 MB RSS.
- **Ice:** abandoned. Last release September 2025, macOS 27 issue open since June 2026 with no maintainer reply.
- **Thaw** (the Ice fork, [thaw-app/Thaw](https://github.com/thaw-app/Thaw)): Thaw 3 is a rewrite for macOS 27, still in beta (3.0.0-beta.6, 2026-11-04). Its source (read 2026-11-05, `docs/ARCHITECTURE.md`, `Thaw/Items/Manager/MenuBarItemManager+ConcealedClick.swift`) is the best first-hand account of how macOS 27 works:
  - *Hiding:* a closed-source component (PlatformRuntimeKit) asks MenuBarAgent to hide an app's items, so hiding is per app: all of one app's items hide together. Its "Native" method flips the per-app switches of System Settings → Menu Bar → Allow in the Menu Bar instead, which are stored in `~/Library/Group Containers/group.com.apple.controlcenter/…/group.com.apple.controlcenter.plist`.
  - *Order:* macOS 27 keeps the menu-bar order in one protected file under `~/Library/Group Containers/com.apple.MenuBar`. Other apps cannot read it (`Operation not permitted`, even from Terminal) until the user picks it in an open panel (Thaw calls this "Menu Bar Layout Access"; Full Disk Access is the fallback). Thaw writes positions there; synthetic ⌘-drag is its fallback.
  - *Opening a hidden item:* Thaw does **not** open it under the Thaw Bar. It reveals the item where it sits in the real menu bar, presses it there, and hides it again after the menu closes. `AXShowMenu` opens an item's secondary (right-click) menu, also at the item's real position.
  - *Permissions:* Accessibility required, Layout Access for ordering, Screen Recording optional (without it the Thaw Bar shows app icons, like dotbar).
- **Verdict:** nobody can open another app's menu or popover anywhere except under that app's own icon in the real menu bar. The app positions its menu itself, from its status item's frame. A manager can only choose where that icon is drawn at the moment it is pressed.

## macOS 27 menu bar, measured through Accessibility (2026-11-05)
- `MenuBarAgent` (`com.apple.MenuBarAgent`) has one AX window, the full menu-bar strip (1920x30 here). Its children are one `AXGroup` (subrole `AXHostingView`) per status item, of every app. Inside each group is the item's own element, owned by the item's app (`AXUIElementGetPid` gives the owner). So one walk of this window is a complete inventory with owners. It also lists items that are parked behind the overflow arrow, which the apps' own `AXExtrasMenuBar` do not list while parked. dotbar's `menuBarItems()` uses it since 2026-11-05 (it found Outlook, which the old per-app walk missed).
- MenuBarAgent's own `AXExtrasMenuBar` lists Apple's items (`com.apple.menuextra.battery`, `.sound`, `.wifi`, `.controlcenter`, `.clock`) as `AXMenuBarItem` with `AXShowMenu`, `AXPress`, a "Remove from Menu Bar" custom action, and `AXImageData` (an array of PNGs: the real glyph, readable without Screen Recording). Third-party items have no `AXImageData`.
- **Apple's overflow arrow:** an `AXButton` with `AXIdentifier` `menu-bar-overflow-indicator`, description "Show Hidden Menu Bar Items", at the left end of the status area. It exists only while some items do not fit. `AXPress` on it expands the overflow **inline**: the parked items are drawn in the real menu bar to the left (x≈435–948 here, over the app menus), and the arrow becomes `menu-bar-overflow-indicator-expanded`, "Hide Menu Bar Items". Pressing that collapses it again.
- Parked items keep an AX frame (their parked x), but **`AXPress` on a parked item opens nothing** (tested with Kerberos: no menu window appeared). An item must be drawn to open.
- Whether a pushed item is hidden depends on the frontmost app: with long app menus the item is parked behind the arrow; with short ones it is drawn next to the app menus, and the arrow disappears. This is why pushing never hides reliably on macOS 27.

## Short app menus leave hidden icons visible (measured 2026-11-05)
- The room left of the status items depends on the frontmost app (see above), so a separator width fitted with Edge in front is far too short with Herdr (one menu): about ten hidden icons stayed drawn. Re-fitting on every app activation fixes most of it.
- Even re-fitted, with Herdr in front macOS clamped the separator's left edge at x=137 and kept the one icon (Outlook, 112-135) in the gap between the app menus and the separator: growing further was refused (frame `137..1074`, the right edge moved instead), not answered by dropping that icon.
- A 1-point item of dotbar's own placed next to the separator did not help (both survived). A **40-point** invisible item there did: the separator then reached x=113 and nothing hidden stayed drawn. The spacer is 1 point while expanded.
- Writing `TrailingItemPreferredPositions` through `CFPreferencesSetValue` with the file's absolute-path domain reached the file (cfprefsd), and MenuBarAgent placed the new item where written.

## Laptop screen alone (notch), measured 2026-11-05
Built-in display 1280x828 points; the notch spans x≈570–710 (`NSScreen.auxiliaryTopLeftArea`/`TopRightArea`). The operator's screenshots and AX reads agree:
- macOS fills the status area right of the notch (~550 pt) from the right. What does not fit is **parked** behind the « chevron (stacked at x≈739–748). Pressing « draws the parked items inline left of the notch, over the app menus, and they work natively.
- What does not fit even there is **dropped**: no MenuBarAgent group, and the owning app's `AXExtrasMenuBar` returns `kAXErrorNoValue` (-25212). Dropped here: dotbar's own separator and the five items left of it. With short app menus (no chevron) more fits: Outlook came back at x≈128.
- **A dropped item leaves no AX trace**: neither the app nor MenuBarAgent exposes it, and expanding « does not bring it back. The only hint is MenuBarAgent's analytics key `MenuBarAnalytics.lastReportedTrailingItemCount` (29 vs 24 groups drawn), which names nothing.
- **But an element obtained while the item was visible keeps working** while its app runs: GlobalProtect's element, read on the external display, opened its popover after the switch to the laptop (popover placed right of the notch). Untested for plain-menu items such as Kerberos.
- While the menu bar is off screen (full-screen app, display asleep), MenuBarAgent's window reads as 0x0 with no children.
- Thaw's hide/reveal call to MenuBarAgent lives in its closed PlatformRuntimeKit, whose license forbids taking it apart to rebuild elsewhere. Not used, not inspected.

## Hiding by pushing (the Hidden Bar / Ice trick) is fragile on macOS 27
- Idea: a status item ("separator") made very wide pushes the items on its left off-screen.
- On macOS 27 an item wider than the room it has is **ignored/dropped**: a 10000 px separator does nothing. Probed widths: up to ~800 px worked, 1200+ px was dropped (all icons came back).
- The left limit depends on the **frontmost app's menu width** (the status area starts right of the app menus): clamp `minX` was 113 px with one app in front, ~400 with another.
- `NSStatusItem` window frames update **asynchronously** (about 80 ms); reading them straight after setting `length` gives stale values.
- Even with the stepwise growth in `grow()`, on a large display some icons stay stuck at the far left with a gap after them. Verdict: pushing cannot be made to hide reliably (see the overflow measurements above for the reason).
- `defaults write <app> "NSStatusItem Visible <autosaveName>" -bool false` hides an item, but **only when that app launches**; changing it while the app runs has no effect (tested with and without restarting cfprefsd). Not usable as a live toggle. `com.apple.controlcenter` still stores Apple's own items this way (`NSStatusItem VisibleCC …`, `NSStatusItem Preferred Position …`).

## Accessibility is enough to list and press items (no Screen Recording)
- Items expose `AXPosition`/`AXFrame`, `AXTitle`/`AXDescription` and `AXPress`. Some apps expose live text (iStat Menus: "CPU 15%", "Battery: 100%, Charged.").
- `CGWindowListCopyWindowInfo` does not list per-item windows on macOS 27 (only one Window Server strip at layer 24), so use AX.
- Apple's agents without a real app icon (`KerberosMenuExtra`, `TextInputMenuAgent`) get SF Symbols in the bar.
- Pressing an item pushed off-screen or parked opens nothing visible. What works: bring the item on screen, wait ~0.5 s, `AXPress`. Verified with Kerberos.
- Not verified yet: the laptop screen alone (notch, no external display). Open questions: where do parked items go when the inline overflow expands next to the notch, and does the arrow exist there at all?

## Permissions gotchas on macOS 27
- The Accessibility pane is now called **"Device Control and Data Access"**. Deep link: `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`.
- An ad-hoc signed build gets a new identity on every rebuild, so macOS silently invalidates the grant: the toggle still looks ON but `AXIsProcessTrusted()` is false and the item list is empty. Fix: a stable self-signed signing certificate (see [KB.md](KB.md#signing)).
- `log` is shadowed by a zsh builtin: use `/usr/bin/log show ...` (tccd, replayd, MenuBarAgent subsystems were useful).
- GitHub occasionally returns an Internal Server Error on push; a retry minutes later worked.
