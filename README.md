# Omnibar

Windows-style taskbar for macOS. One bar per display, per-window switching, hover thumbnails, pinning, Spaces support, and a Start Menu.

It runs as a menu-bar accessory (`LSUIElement`): there is no Dock icon except during first-run onboarding. Open **Settings…** from the menu extra, or click the app again after it is already running.

Minimum macOS: 14. Built with Swift 6 and AppKit.

## Install

```bash
brew install --cask specktronica/omnibar/omnibar
```

After install, grant **Accessibility** in System Settings. **Screen Recording** is optional (live hover thumbnails).

## Build

```bash
./scripts/bootstrap.sh
./scripts/build.sh
open build/Omnibar.app
```

`bootstrap.sh` generates `Omnibar.xcodeproj` with XcodeGen. `build.sh` produces `build/Omnibar.app`, signed with the "Apple Development" identity from your keychain when one is installed, or ad-hoc otherwise. Set `CODESIGN_IDENTITY` to pick a specific identity. Default configuration is Release.

```bash
make build    # same as ./scripts/build.sh
make run      # build, kill a running Omnibar, open build/Omnibar.app
make release  # Developer ID sign, notarize, staple, zip to build/Omnibar-<version>.zip
```

Or open the generated project:

```bash
./scripts/bootstrap.sh
open Omnibar.xcodeproj
```

The Xcode project is gitignored; `project.yml` is the source of truth.

## Permissions

- **Accessibility** (required): list windows, raise / minimize / close / fullscreen, and read Dock badges.
- **Screen Recording** (optional): live hover thumbnails. Without it, the preview shows the app icon and title.

macOS records permission grants against the app's code-signing requirement. With a real signing identity the requirement is based on bundle ID and team, so grants survive rebuilds. With an ad-hoc signature the requirement is a per-build `cdhash`, so every rebuild needs a fresh grant: System Settings still shows Omnibar as enabled, but the new binary is not trusted. If that happens, remove the stale entry and grant again:

```bash
tccutil reset Accessibility io.specktronica.omnibar
tccutil reset ScreenCapture io.specktronica.omnibar
```

Run only one copy of Omnibar at a time. Two builds with different signatures share the same bundle ID, and only one can match the recorded grant.

Launch at login is on by default (`SMAppService`) and can be toggled in Settings → General.

Signing, TCC, and tests are covered in [docs/development.md](docs/development.md).

## Features

- Taskbar at the bottom of each screen, matching the system light/dark appearance (or forced dark)
- Start button: Start Menu, Launchpad, or Spotlight (right-click to choose)
- Start button logo: color presets, or pick each lobe
- Start Menu with search, A–Z app list, pinned grid, and recent apps
- Per-window tiles with icon, title, and Dock badges; click to raise, click the active tile to minimize (or hide)
- Middle-click a tile for New Window
- Hover thumbnails with configurable delay and size
- Keep in Taskbar, blacklist, New Window, Hide, Quit, Fullscreen, Minimize, Close
- Spaces: show windows on the current Space; hide the bar in fullscreen Spaces
- Drag to reorder, group by application, icons-only mode
- Multi-monitor: one bar per screen, main-display-only, hide per display
- Auto-resize overlapping windows, fully hide Dock (moved to the top, including Mission Control, reverted on quit), auto-hide the bar

See [docs/usage.md](docs/usage.md) for clicks, menus, and every Settings pane.

## Known limitations

- Space membership and fullscreen detection use private SkyLight / CGS symbols (`CGSCopyManagedDisplaySpaces`, `CGSCopySpacesForWindows`, and related). Those can change with macOS releases.
- Fully hiding the Dock moves it to the top (so it cannot share Omnibar's edge) and uses `CGSSetWindowLevel` on Dock strip windows during Mission Control. Autohide delay alone cannot hide that strip; it is part of Mission Control's overlay.
- Launchpad was removed on some macOS 26 installs. If Launchpad cannot be opened, the Start button falls back to Spotlight.
- Ad-hoc signed local builds are not notarized and are not sandboxed. Accessibility and screen capture need the unsandboxed app.
- Window IDs are not stable across logout. Pin order is persisted; in-session window order is not.

## Tests

```bash
./scripts/bootstrap.sh
xcodebuild -project Omnibar.xcodeproj -scheme Omnibar -destination 'platform=macOS' test
```

## Documentation

- [Usage](docs/usage.md) — taskbar, Start Menu, settings, and defaults
- [Architecture](docs/architecture.md) — process layout, scan pipeline, persistence
- [Development](docs/development.md) — generate, build, sign, permissions, tests
