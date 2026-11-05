# dotbar: context for Claude

macOS menu-bar manager (Swift/AppKit, plain `swiftc`). Goal: hide menu bar icons and show them in a **second bar below the menu bar**, cheap on resources, because Bartender 6 is broken on macOS 27.2. The user (Marco) uses a notched MacBook Air 15" M3, often without an external display, where there is no room in the menu bar.

**Read `docs/FINDINGS.md` first**: it records what was measured on macOS 27 (pushing trick limits, Accessibility API, permission gotchas), what works, and the open questions. Top open question: behaviour on the laptop screen alone, where macOS drops icons itself.

Rules: stay Accessibility-only (no Screen Recording), no dependencies, idle CPU near 0, no polling. Build/run: `scripts/build-app.sh --install`. Debug log: `/tmp/dotbar.log`. Cannot take screenshots from the agent side (no Screen Recording for the terminal), so ask Marco to look and report what he sees. Commit and push after every change (repo `Marcus1571/dotbar`, public); never commit secrets; the signing certificate lives only in the login keychain.
