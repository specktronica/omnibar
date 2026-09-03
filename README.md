# Omnibar

Windows-style taskbar for macOS. One bar per display, per-window switching, hover thumbnails, pinning, Spaces support, and a Start Menu.

Minimum macOS: 14. Built with Swift 6 and AppKit.

## Build

```bash
./scripts/bootstrap.sh
./scripts/build.sh
open build/Omnibar.app
```

`bootstrap.sh` generates `Omnibar.xcodeproj` with XcodeGen. `build.sh` produces `build/Omnibar.app`, signed with the "Apple Development" identity from your keychain when one is installed, or ad-hoc otherwise. Set `CODESIGN_IDENTITY` to pick a specific identity.

Or open the generated project:

```bash
./scripts/bootstrap.sh
open Omnibar.xcodeproj
```

## Permissions

- **Accessibility** (required): list windows, raise / minimize / close / fullscreen, and read Dock badges.
- **Screen Recording** (optional): live hover thumbnails. Without it, the preview shows the app icon and title.

macOS records permission grants against the app's code-signing requirement. With a real signing identity the requirement is based on bundle ID and team, so grants survive rebuilds. With an ad-hoc signature the requirement is a per-build `cdhash`, so every rebuild needs a fresh grant: System Settings still shows Omnibar as enabled, but the new binary is not trusted. If that happens, remove the stale entry and grant again:

```bash
tccutil reset Accessibility io.specktronica.omnibar
tccutil reset ScreenCapture io.specktronica.omnibar
```

Run only one copy of Omnibar at a time. Two builds with different signatures share the same bundle ID, and only one can match the recorded grant.

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
- Auto-resize overlapping windows, fully hide Dock including Mission Control (reverted on quit), auto-hide the bar

## Known limitations

- Space membership and fullscreen detection use private SkyLight / CGS symbols (`CGSCopyManagedDisplaySpaces`, `CGSCopySpacesForWindows`, and related). Those can change with macOS releases.
- Fully hiding the Dock in Mission Control uses `CGSSetWindowLevel` on Dock strip windows. Autohide delay alone cannot hide that strip; it is part of Mission Control's overlay.
- Launchpad was removed on some macOS 26 installs. If Launchpad cannot be opened, the Start button falls back to Spotlight.
- Ad-hoc signed local builds are not notarized and are not sandboxed. Accessibility and screen capture need the unsandboxed app.
- Window IDs are not stable across logout. Pin order is persisted; in-session window order is not.

## Tests

```bash
./scripts/bootstrap.sh
xcodebuild -project Omnibar.xcodeproj -scheme Omnibar -destination 'platform=macOS' test
```
