# Findings (macOS 27.2 "Golden Gate", build 26B123)

Research log: what was measured or read, with verdicts. Current state and next steps live in [STATUS.md](STATUS.md); how dotbar works lives in [KB.md](KB.md).

Measured on a MacBook Air 15" M3 (notch), Swift 6.4.2 with Command Line Tools only (no Xcode; plain `swiftc`). External display: 4K scaled to 1920x1080 points. Treat numbers as examples; the point is the behaviour.

## The parked-inline leak, measured live (2026-11-13, external display 2048x858 pt, Herdr in front)
Reported by the operator: hidden icons reappeared in the real menu bar next to the "Herd" app menu (iStat Menus Disks and Sensors, later also Teams), while dotbar's log said `squeeze: 0 hidden icon(s) drawn left of the separator`. Three separate behaviours, all measured with paired `screencapture -R` crops (ground truth) and AX walks of MenuBarAgent's window:

- **macOS draws parked items inline next to short app menus, and AX keeps reporting them parked.** With the separator grown to ~1018 pt (left edge pinned at 247), a chevron existed at 1251 with Disks/Sensors/Teams stacked on it (AX frames 1240–1268, overlapping the chevron) — while the screen drew two of them at x≈90–230, right after "Herd". The AX frames of *parked-and-inline-drawn* items are the parked cluster, not where they are drawn, so no AX read can see the leak. This is a new trap beyond the known "short menus keep one icon drawn": there the items were not parked and their frames told the truth.
- **The spacer overshoot defeats itself.** The squeeze's old increment set the spacer to `40 + (sep − leftmost drawn x)`. macOS draws a status item ~3 pt wider than its set length, and drops it entirely when that exceeds the available gap — handing the room back to the icons (measured: set 400 in a ~208 pt gap → spacer dropped, two icons drawn at 273–319; set 40 → spacer drawn at 43 pt). So a wider set length is *worse* past the gap: the correct value is the gap itself, minus the ~4 pt of padding.
- **macOS re-packs the bar seconds after a length change.** Right after a fresh launch the grow dance and squeeze both ended on a state where the icons were still parked (blind read, "0 drawn"); a probe ~15 s later showed them drawn at x=138–212 with truthful frames. No in-dance timing (80 ms frames, 300 ms squeeze steps) sees the final layout.

- **Fix (0.3.2):** the spacer is set to exactly `separator minX − end of the frontmost app's menus − 4`, where the menus end is read from the frontmost app's own `AXMenuBar` (last menu item's `AXFrame.maxX`; Herdr: 101, Edge: 592). That anchor is stable no matter how macOS's transient re-packs move the icons, it covers the blind parked-inline state (the spacer eats the gap the inline drawing would use), and it needs no knowledge of where the icons are. A `settleCheck` re-runs the squeeze once, 2 s after every finished squeeze round (max 4 rounds), for the late re-pack. Verified live: with Herdr in front the dance converges to `0 hidden icon(s) drawn, spacer 214 covering x=101..319` within ~1 s and the menu bar shows nothing between "Herd" and the status area; idle CPU stays 0.0% (one-shot timers, no polling).
- Not verified: the laptop screen alone (the notch's inline drawing zone is the notch's left edge, not the menus end — the anchor may under-cover there; the old laptop limits apply regardless).

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
- The gap is not always one icon: once, with Herdr in front, the separator stopped at x=235 and two iStat Menus icons plus the 40-point spacer stayed in it. Hence the measured widening (`squeeze`).
- A pushed separator's right edge is not fixed: when the order puts text items (iStat Menus) between the separator and the dot, their width changes move it. Judging push steps by the right edge made every step look refused (2026-11-06, Excel in front: nothing was pushed). The left edge is the reliable signal: accepted steps move it left by the step, refused ones leave it pinned at the app menus while the frame overflows right.
- Writing `TrailingItemPreferredPositions` through `CFPreferencesSetValue` with the file's absolute-path domain reached the file (cfprefsd), and MenuBarAgent placed the new item where written.

## Laptop screen alone (notch), measured 2026-11-05
Built-in display 1280x828 points; the notch spans x≈570–710 (`NSScreen.auxiliaryTopLeftArea`/`TopRightArea`). The operator's screenshots and AX reads agree:
- macOS fills the status area right of the notch (~550 pt) from the right. What does not fit is **parked** behind the « chevron (stacked at x≈739–748). Pressing « draws the parked items inline left of the notch, over the app menus, and they work natively.
- What does not fit even there is **dropped**: no MenuBarAgent group, and the owning app's `AXExtrasMenuBar` returns `kAXErrorNoValue` (-25212). Dropped here: dotbar's own separator and the five items left of it. With short app menus (no chevron) more fits: Outlook came back at x≈128.
- **A dropped item leaves no AX trace**: neither the app nor MenuBarAgent exposes it, and expanding « does not bring it back. The only hint is MenuBarAgent's analytics key `MenuBarAnalytics.lastReportedTrailingItemCount` (29 vs 24 groups drawn), which names nothing.
- **But an element obtained while the item was visible keeps working** while its app runs: GlobalProtect's element, read on the external display, opened its popover after the switch to the laptop (popover placed right of the notch). Untested for plain-menu items such as Kerberos.
- While the menu bar is off screen (full-screen app, display asleep), MenuBarAgent's window reads as 0x0 with no children.
- Thaw's hide/reveal call to MenuBarAgent lives in its closed PlatformRuntimeKit, whose license forbids taking it apart to rebuild elsewhere. Not used, not inspected.

## Seating a clicked item next to the separator (2026-11-11)

The shelved "seat beside the dot" idea (STATUS 2026-11-05) became possible once dotbar had layout-write access (2026-11-05): a *dropped* item cannot be dragged, but its preferred position can be written. Decision, with the reasoning:

- **The seat goes just right of the separator (`separator value − 0.5`), not left of it.** While pushed, the separator's window spans the whole hidden zone (measured: `frame=114..1103` at width 986) with its left edge clamped at the app menus, and the icons left of it are **dropped, not parked** on this display (`scan` logs `chevron=none` + `OFFBAR`) — a position left of the separator cannot be drawn anywhere. Right of the separator is the zone that always draws (the dot's zone), on every display.
- **The separator's length is temporarily reduced by about the seated item's width** (`max(24, w + 8)`): seating one more icon into a chain whose left edge is already clamped would make macOS drop or clamp the separator (flood-back). With the length reduced, the whole chain fits deterministically. On restore, the push is re-tightened from the current width (refit-style), not from narrow, so nothing flashes back.
- **Right-click on a below-bar icon maps to `AXShowMenu`** (the item's secondary menu, same call Thaw uses), falling back to `AXPress`; left-click stays `AXPress`. NSButton ignores right clicks, so the bar's buttons are a small subclass. Measured the same day on real items: every third-party item rejects `AXShowMenu` (AXError -25206, unsupported action), and **BetterDisplay accepts `AXPress` (AXError 0) but opens no menu** on an item that just appeared — while a manual click on the seated icon worked. So the seated paths now press with a **real synthetic click** (`CGEvent` posted at the item's drawn frame, left or right button per the click), which is the faithful "equivalent of a right click"; the accessibility press stays for items already on the bar (drawn/parked), where it is proven, and as the fallback if the events cannot be posted. The pointer moves to the icon for the moment of the click, as with any click.
- **Restore trigger:** the next mouse click — global *and* local monitor, because the old global-only monitor could not see clicks on dotbar's own UI — or Escape/Return/Enter. Navigation keys are excluded so an open menu remains usable while the item stays seated (the old monitor collapsed the chevron on any key).
- **Key matching:** items have no stable identifier an AX read would give, but the layout file keys do (`status:<owner>::<autosave>`); owner matches by bundle id or localized name, and multi-item apps (iStat Menus runs six) are matched by the item's left-to-right order on the scan where they all showed, since the file's value order is the menu-bar order. Ghosts (no order known) are seated only when the app has exactly one key.
- **Not verifiable from the agent's seat** (only dotbar holds the grant to the layout file): whether a dropped item re-appears live at its seat position on both displays, and how a packed laptop bar reacts (the seat may displace the leftmost visible icon into the chevron for the moment). Verify by clicking a below-bar icon with `/tmp/dotbar.log` open: `seat:` lines show the write, the shrink and the restore; `press … path=seated` shows the AX result; `path=absent` after a `seat: item did not appear` means the fallback ran.

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

## Screenshots and real clicks from an agent session (measured 2026-11-12)
- The session host now holds **Screen Recording**: `screencapture -x -R<x,y,w,h>` captures real screen content and the agent can view the PNG itself (the AGENTS.md "no Screen Recording" note was stale; fixed the same day). `osascript`/System Events has Accessibility too, so the full AX walk works from the session.
- **AX press/click on dotbar's own dot does nothing**: `click()` guards on `NSApp.currentEvent`, which an accessibility press does not produce (`main.swift`). A real synthetic click works: a tiny Swift probe posting a `CGEvent` mouse-down/up pair to `.cghidEventTap` at the dot's AX frame opens the bar. Same for the bar's buttons — a real click on the BetterDisplay button ran the full `seat:` → `press … path=seated` path and its menu opened at the seat (frame 933..952), matching the operator's manual verification of 2026-11-11.
- Escape (System Events `key code 53`) closes the opened menu, and the seat restores itself within ~1 s (`seat: restored`). Opening a menu is passive; nothing is invoked.
- AX positions and `screencapture -R` share one global coordinate space; with the lid closed there is a single display (the 4K external at 1920x1080, 2x), so `-R` crops land exactly where AX says. README screenshots (`docs/bar-light.png`, `docs/bar-dark.png`, `docs/menu-open.png`) were taken this way, light and dark via an appearance-preferences toggle that was reverted after.
- Verdict: the agent can fully photograph and drive dotbar's UI; what still needs the operator is only what needs hands (unplugging a display) or taste. Annotating the shots (red rings around the dot and the seated icon) worked with ImageMagick `magick -draw roundrectangle`; a hand-rolled CoreGraphics stroke over an `NSBitmapImageRep` context drew unreliably (rings silently missing on some runs).

## NSMenuItem.image does not render in dotbar's menu on macOS 27 (2026-11-14, porting Report a Bug)

While porting the siblings' "Report a Bug" item to dotbar (0.4.0), the ladybug
SF Symbol set on the menu item (`NSMenuItem.image`, explicitly built with
`NSImage(systemSymbolName: "ladybug.fill")` + a 13 pt symbol configuration)
never appeared in the dot's right-click menu — the identical item renders fine
in diskled-plus's menu (same macOS build, same day).

What was ruled out, with evidence:
- The image is set at runtime: a debug log line printed
  `bug item image=set size=(18.0, 18.0) template=true` right after the
  assignment; the item itself renders (title, target/action, position all
  correct in AX and screenshots).
- Menu display mode: tried dotbar's transient trick
  (`dot.menu = m; performClick; dot.menu = nil`) AND a persistent
  `dot.menu = m` (temporarily left set) — no icon either way.
- `NSHighResolutionCapable`: dotbar's Info.plist lacked it (both siblings have
  it); adding it did not change menu icon rendering (kept anyway — it belongs
  in every modern app).
- Standalone rendering: the exact same image call works in a plain script and
  in dotbar's own About window (the bug row's ladybug `NSImageView` renders).
- Automatic menu icons (macOS 26+): dotbar's menu DOES get them (a ⚙ appeared
  on "Settings…" with no explicit image), but no automatic ladybug was
  supplied for "Report a Bug…" — while diskled-plus's identical item shows a
  *colored* ladybug (suggesting diskled's icon may itself be the automatic
  system at work, not the explicit template image).

Verdict: unexplained macOS 27 rendering difference between the two apps'
menus; the honest adaptation is the operator's originally suggested emoji in
the title (`🪲 Report a Bug…`), which renders everywhere. If a future macOS
build renders it, the SF Symbol image is a one-line revert.

## CGEvent clicks from the agent session stopped working mid-session (2026-11-14)

During the same session, synthetic CGEvent clicks (which drove dotbar's menu
opens for screenshots at ~18:44–18:51, and worked in prior sessions per the
recipe above) stopped opening ANY app's menu-bar menu — dotbar's and
diskled-plus's alike — while CGEvent mouse *moves* still landed (hover
tooltips appeared). AX clicks still reached items but dotbar's right-click
menu needs a real rightMouseUp event, so it stopped being openable. Verified
the new surfaces instead via a temporary env-var-gated auto-open build
(`DOTBAR_ABOUT_VERIFY`/`DOTBAR_BUG_VERIFY` in applicationDidFinishLaunching,
removed before release): the About window was captured headlessly and
`reportBug()`'s `NSWorkspace.open` brought the browser forward. Lesson: when
synthetic clicks go dark mid-session, fall back to launch-time hooks rather
than retrying the click path.

## 0.4.0 hotfix: a duplicate NSMenu add silently killed the dot's menu (2026-11-14)

The 0.4.0 edit left the Report a Bug item in the menu **twice**: the switch to
the `m.addItem(withTitle:action:keyEquivalent:)` convenience (which already
inserts the item) was layered over a leftover explicit `m.addItem(bug)` from
the previous construction. AppKit throws an internal-inconsistency exception
on adding an item that is already in a menu; the exception fired mid-way
through `click()`'s menu build on every right-click, so the menu never
displayed — with **no trace in dotbar's log** (the log() lines around it never
ran; an ObjC exception in Swift aborts the call stack silently).

Verified after removing the leftover line: the right-click menu opens again
(CGAEvent right-click, screenshot), and the emoji title renders in place of
the never-rendering SF Symbol image.

Lessons: (1) when switching an item between `addItem(withTitle:)` and an
explicit `NSMenuItem` + `addItem(_:)`, check for a leftover second add —
AppKit's duplicate-add exception is invisible without a log line inside the
menu build; (2) the earlier "CGEvent clicks stopped working" scare (§CGEvent
entry) and this bug overlapped in the session — the menu was genuinely broken
by the double-add from the installed 0.4.0 onward, so not every later
no-menu capture was the synthetic-click problem.
