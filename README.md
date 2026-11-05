# dotbar

A tiny macOS menu-bar manager: icons you do not need every day move out of the way, and a **second bar below the menu bar** lists them; click one to open it. Native Swift/AppKit, one process, about 0% CPU, no Screen Recording, no network, no dependencies.

Built because Bartender 6 stopped working on macOS 27, which draws every menu-bar icon in one shared window and broke every manager that moved icon windows around ([what changed](findings.md#why-the-other-menu-bar-managers-broke-on-macos-27-read-2026-11-05)). **Status: work in progress**, working but rough; see [STATUS.md](STATUS.md).

## How it works
- dotbar puts a dot and a separator in the menu bar; [icons left of the separator are the hidden ones](KB.md#hiding-pushing).
- Click the dot and a small [bar appears under the menu bar](KB.md#the-bar-below-the-menu-bar) with those icons (app icons, live text where the app exposes it). Click one and [its real menu opens](KB.md#opening-an-item).
- Click the slider at the end of the bar to choose which icons live there (⌘-drag them across `┃`).
- Right-click the dot to arrange icons, refresh the list, launch at login or quit.

## Permissions
**Accessibility** only, which macOS 27 calls *Device Control and Data Access*. dotbar never asks for Screen Recording ([details](KB.md#permissions)).

## Build
`scripts/build-app.sh --install` builds with plain `swiftc`, installs to `~/Applications` and launches; [signing keeps the Accessibility grant across rebuilds](KB.md#signing).

Everything else, from the inventory walk to the debug log, is in the [knowledge base](KB.md).
