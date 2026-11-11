# AGENTS.md

**Before anything else:** at the start of every session, read `GOVERNANCE.md` and `USER.md` from the operator's Obsidian vault on the home server (host, path and access are in the operator's private infra notes, never in this repo). They hold the operator's cross-project defaults. Where they and this file disagree on a project-specific fact, this file wins; cross-cutting principles (secrets handling, caution with destructive actions and the like) still apply here regardless.

## What this project is
A macOS menu-bar manager (Swift/AppKit, plain `swiftc`): hide menu-bar icons and show them in a **second bar below the menu bar**, cheap on resources. Built because Bartender 6 is broken on macOS 27. The operator uses a notched MacBook Air 15" M3, often without an external display, where there is no room in the menu bar.

## Read first
[STATUS.md](STATUS.md) (where things stand, the next step), then [findings.md](findings.md) (what macOS 27 does, measured), then [KB.md](KB.md) (how dotbar works).

## Rules
- Accessibility, plus (optional, for profiles) access to the one menu-bar layout file the user picks in an open panel (operator decision 2026-11-05). Never require Screen Recording or Full Disk Access, never touch the network.
- No dependencies. Idle CPU near 0, no polling; check after UI changes with `top -l 3 -s 10 -pid $(pgrep -x dotbar) -stats pid,cpu,idlew`.
- Build and run: `scripts/build-app.sh --install`. Debug log: `/tmp/dotbar.log`.
- The agent cannot take screenshots (the terminal has no Screen Recording). It *can* read the live menu bar through Accessibility from small Swift probes, so measure first and ask the operator only for what needs eyes (what appears on screen) or hands (unplugging a display).
- Commit, push and publish are one flow (operator, 2026-11-05): every change to the app is committed, its CHANGELOG bullet added under `## Unreleased`, then released with `scripts/release.sh X.Y.Z` (patch bump per change; it sets the version, tags, pushes and creates the GitHub Release). Docs-only changes: commit and push. Repo `Marcus1571/dotbar`, public. Never commit secrets; the signing certificate lives only in the login keychain. Keep the docs generic: no hostnames, IPs or personal item lists.
- **Publishing additions since 0.3.0** (mirroring usagebar and diskled-plus): after `scripts/release.sh`, run `scripts/make-dmg.sh` — it rebuilds the app Developer ID-signed (hardened runtime, timestamp), makes the DMG, notarizes it through the shared `diskledplus-notary` keychain profile, staples and validates — then attach the DMG to the release with `gh release upload v<version> build/dist/dotbar-<version>.dmg`. Dev installs keep the default `dotbar local signing` certificate (same Accessibility grant across rebuilds); switching an installed copy to the Developer ID identity invalidates the grant once and needs a re-grant. The app icon is generated at build time by `scripts/make-icon.swift` — never commit binary assets.
