# Findings (macOS 27.2, Nov 2026)

Everything below was measured on a MacBook Air 15" M3 (notch), macOS 27.2 "Golden Gate", Swift 6.4.2 with Command Line Tools only (no Xcode; plain `swiftc`). External display: 4K scaled to 1920x1080 points. Treat numbers as examples; the point is the behaviour.

## Why this project exists
- Bartender 6.5.0 shows Screen Recording as missing although macOS grants it: `tccd` logs `authValue=2 authReason=4` (allowed, set by user) for `com.surteesstudios.Bartender`, and `replayd` re-checks it about every 15 s. Resetting (`tccutil reset ScreenCapture`) and re-granting changed nothing, and the app idles at about 175 MB RSS. Looks like a Bartender / macOS 27 incompatibility, not a permission problem.
- Ice (the open-source alternative) looks abandoned: last release 0.11.12 two years ago, last commit last year.

## Hiding by pushing (the Hidden Bar / Ice trick) is fragile on macOS 27
- Idea: a status item ("separator") made very wide pushes the items on its left off-screen.
- On macOS 27 an item wider than the room it has is **ignored/dropped**: a 10000 px separator does nothing. Probed widths: up to ~800 px worked, 1200+ px was dropped (all icons came back).
- The left limit depends on the **frontmost app's menu width** (the status area starts right of the app menus): clamp `minX` was 113 px with one app in front, ~400 with another.
- `NSStatusItem` window frames update **asynchronously** (about 80 ms); reading them straight after setting `length` gives stale values.
- `dotbar` therefore grows the separator in steps (64, 16, 4 px) and keeps the last width macOS accepted (see `grow()` in `Sources/dotbar/main.swift`).
- Even so, on a large display some icons stay stuck at the far left, with a gap after them: macOS never needs to drop them. Pushing cannot be made to hide reliably.
- `defaults write <app> "NSStatusItem Visible <autosaveName>" -bool false` hides an item, but **only when that app launches**; changing it while the app runs has no effect (tested with and without restarting cfprefsd). Not usable as a live toggle.
- No public API hides another app's menu bar item. Bartender-style tools use hacks (pushing, simulated Cmd+drag, window capture).

## Accessibility is the way to see and press other apps' items (no Screen Recording)
- Per running app, `AXExtrasMenuBar` exposes its menu bar items. Each has `AXPosition`, `AXSize`, `AXTitle` / `AXDescription` and the `AXPress` action. Some apps expose live text (iStat Menus: "CPU 15%", "Battery: 100%, Charged.").
- Status items on macOS 27 are hosted by `com.apple.MenuBarAgent` scenes: `CGWindowListCopyWindowInfo` does not list them (no layer 25 windows), so use AX.
- Apple's own agents (`KerberosMenuExtra`, `TextInputMenuAgent`) have no real app icon (generic placeholder), so the bar maps them to SF Symbols.
- **Pressing an item that is pushed off-screen opens nothing visible.** Working flow: expand the separator so the item is on-screen, wait ~0.5 s, `AXUIElementPerformAction(AXPress)`, re-collapse after the next click anywhere. Verified: pressing Kerberos from the bar opened its real menu.
- Not verified yet: what AX reports for items macOS drops by itself when there is no room (laptop alone). That is the key open question.

## Permissions gotchas on macOS 27
- The Accessibility pane is now called **"Device Control and Data Access"**. Deep link: `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`.
- An ad-hoc signed build gets a new identity on every rebuild, so macOS silently invalidates the grant: the toggle still looks ON but `AXIsProcessTrusted()` is false and the item list is empty. Fix 1: `tccutil reset Accessibility local.dotbar`, relaunch, re-grant. Fix 2 (done): sign with a stable self-signed certificate. `dotbar local signing` lives in the login keychain (created with `openssl` plus `security import`, EKU codeSigning; it shows `CSSMERR_TP_NOT_TRUSTED` in `find-identity` but codesign accepts it). The designated requirement is `identifier "local.dotbar" and certificate leaf = H"15089f59..."`, which survives rebuilds. `scripts/build-app.sh` uses it automatically and falls back to ad hoc. The certificate and key are NOT in the repo; recreate them if the keychain is lost.
- `log` is shadowed by a zsh builtin: use `/usr/bin/log show ...` (tccd, replayd, MenuBarAgent subsystems were useful).
- GitHub occasionally returns an Internal Server Error on push; a retry minutes later worked.

## Debugging aids
- `dotbar` writes `/tmp/dotbar.log` on every refresh (trusted flag, separator x, every item with HIDDEN/shown) and one line per press (`AXError` code).
- `~/Applications/dotbar.app` is the installed copy; `scripts/build-app.sh --install` rebuilds, installs and relaunches.

## State of the product
Works: dot + pipe in the menu bar, left-click the dot for the bar below, click an icon to open its real menu, "Arrange icons…" / "Refresh hidden icons" / Quit in the right-click menu, no Screen Recording, about 0% CPU.
Not good enough yet: icons do not stay hidden reliably (see above), and they all come back when you click one.

## Ideas for next time (not decided)
1. **Test on the laptop alone** (no external display): if macOS itself drops the overflow icons and AX still lists them, the bar can be built from "items macOS has no room for", with no pushing at all. This is the user's real use case.
2. A rule for "hidden" that does not depend on pushing: user-chosen list (by bundle id + title), kept in `UserDefaults`; icons macOS cannot show are always hidden.
3. Auto-refresh the hidden list on `NSWorkspace` launch/terminate notifications.
4. Launch at login (`SMAppService`), profiles (named hidden-lists), an icon limit ("show N, hide the rest").
5. Real glyphs instead of app icons would need Screen Recording; stay without unless essential. Live text from AX titles is a cheap partial substitute.
6. Bartender's "double line" feature is a notch-screen bar; our bar below is the equivalent.
