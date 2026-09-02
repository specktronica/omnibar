# Omnibar

Windows-style taskbar for macOS. One bar per display, per-window switching, hover thumbnails, pinning, Spaces support, and a Start Menu.

Minimum macOS: 14. Built with Swift 6 and AppKit.

## Build

```bash
./scripts/bootstrap.sh
./scripts/build.sh
open build/Omnibar.app
```

`bootstrap.sh` generates `Omnibar.xcodeproj` with XcodeGen. `build.sh` produces an ad-hoc signed `build/Omnibar.app`.

Or open the generated project:

```bash
./scripts/bootstrap.sh
open Omnibar.xcodeproj
```

## Permissions

- **Accessibility** (required): list windows, raise / minimize / close / fullscreen, and read Dock badges.
- **Screen Recording** (optional): live hover thumbnails. Without it, the preview shows the app icon and title.

Grant Accessibility to the exact binary you launched. Rebuilding in place can require granting it again.

Launch at login is available in Settings → General (`SMAppService`).

## Features

- Taskbar at the bottom of each screen, matching the system light/dark appearance (or forced dark)
- Start button: Start Menu, Launchpad, or Spotlight (right-click to choose)
- Start Menu with search, A–Z app list, pinned grid, and recent apps
- Per-window tiles with icon and title; click to raise, click the active tile to minimize (or hide)
- Hover thumbnails with configurable delay and size
- Keep in Taskbar, blacklist, New Window, Hide, Quit, Fullscreen, Minimize, Close
- Spaces: show windows on the current Space; hide the bar in fullscreen Spaces
- Drag to reorder, group by application, icons-only mode
- Multi-monitor: one bar per screen, main-display-only, hide per display
- Auto-resize overlapping windows, fully hide Dock (reverted on quit), auto-hide the bar

## Known limitations

- Space membership and fullscreen detection use private SkyLight / CGS symbols (`CGSCopyManagedDisplaySpaces`, `CGSCopySpacesForWindows`, and related). Those can change with macOS releases.
- Launchpad was removed on some macOS 26 installs. If Launchpad cannot be opened, the Start button falls back to Spotlight.
- Ad-hoc signed local builds are not notarized and are not sandboxed. Accessibility and screen capture need the unsandboxed app.
- Window IDs are not stable across logout. Pin order is persisted; in-session window order is not.

## Tests

```bash
./scripts/bootstrap.sh
xcodebuild -project Omnibar.xcodeproj -scheme Omnibar -destination 'platform=macOS' test
```
