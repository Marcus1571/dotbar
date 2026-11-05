# Contributing

Small project, small rules.

1. **No dependencies.** Plain Swift and AppKit.
2. **Least permission.** Accessibility only. Never require Screen Recording.
3. **Never commit secrets.**

Build with `./scripts/build-app.sh`.

## Energy rules

A menu-bar app must be idle when nothing changed: no polling, timers with tolerance, nothing running while collapsed. After a UI change, check idle CPU: `top -l 3 -s 10 -pid $(pgrep -x dotbar) -stats pid,cpu,idlew` should stay near 0.0.
