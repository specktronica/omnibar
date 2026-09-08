# Architecture

Omnibar is a single macOS app target (`io.specktronica.omnibar`) plus a host-app unit-test bundle. UI is AppKit except Settings and onboarding, which are SwiftUI hosted in `NSWindow`s. The process is an accessory app (`LSUIElement` / `NSApplication.ActivationPolicy.accessory`) so it does not appear in the Dock while running.

## Layout

```
Omnibar/
  App/          entry, AppDelegate, menu extra, login item
  Bridge/       Accessibility, SkyLight/CGS, Dock badge AX
  Core/         scan, track, screens, Dock, catalog, thumbnails, actions
  Model/        settings, pins, blacklist, order, snapshots, geometry
  UI/           taskbar, Start Menu, settings, onboarding
  Resources/    assets, entitlements
OmnibarTests/   logic and geometry tests (no live window-server tests)
project.yml     XcodeGen spec
scripts/        bootstrap (XcodeGen), build, package/notarize, Homebrew publish, uninstall, secret scan
```

## Startup

`OmnibarMain` installs `AppDelegate` and runs `NSApplication`. On launch:

1. Load `SettingsStore` from `UserDefaults` and sync the login item.
2. Create the menu extra (`StatusItemController`).
3. Start `AppCatalog` (application directories + recents).
4. Apply Dock hiding from settings (`DockManager`).
5. If Accessibility is trusted, start `WindowTracker` and `ScreenMonitor`. Otherwise show onboarding. The taskbar does not start while onboarding is showing; Continue (or closing the window) posts `.omnibarPermissionsDidChange` after `isShowing` is cleared. Screen Recording is effective for capture only when `CGPreflightScreenCaptureAccess()` was already true at process start. A mid-session grant is pending restart: preflight stays false until relaunch, so onboarding detects the TCC toggle via other processes’ normal-level window titles (`kCGWindowName`). Windows not at the normal window level (menu bar, wallpaper, Dock, Control Center) are ignored because those titles appear without Screen Recording.

On quit, Dock prefs are restored, then tracker, screen monitor, and catalog stop.

## Window list pipeline

```mermaid
flowchart LR
  events[AX observers / workspace / poll] --> tracker[WindowTracker]
  tracker --> scanner[WindowScanner actor]
  scanner --> ax[AXBridge]
  scanner --> cg[CGWindowList]
  scanner --> cgs[CGSBridge]
  tracker --> logic[TaskListLogic]
  logic --> snap[TaskbarSnapshot]
  snap --> screens[ScreenMonitor]
  screens --> panels[TaskbarPanel per display]
```

`WindowTracker` coalesces scans. Triggers include:

- AX notifications on regular apps (window create/destroy, title, miniaturize, focus, move, resize, hide/show)
- `NSWorkspace` launch/terminate/activate/hide/unhide and Space change
- screen parameter changes, settings/pins/blacklist/badge notifications
- a repeating poll (`pollInterval`, minimum 0.5 s)

`WindowScanner` (an actor) builds `WindowInfo` from Accessibility windows crossed with `CGWindowListCopyWindowInfo`. It keeps layer-0 windows of regular apps, skips a hard-coded system set and the blacklist, drops untitled floating windows (`AXFloatingWindow` / `AXSystemFloatingWindow` with an empty title), and drops frames smaller than 40×40 points.

Space membership and “this display is a fullscreen Space” come from private SkyLight symbols loaded in `CGSBridge` (`CGSCopyManagedDisplaySpaces` / `SLS…` and related). `TaskListLogic` then:

- filters to the current Space (unless “show windows from all screens”); minimized windows remain on their last screen
- optionally collapses same-title tabs
- groups by application or emits one tile per window
- inserts pinned launchers for bundle IDs with no open windows
- applies `OrderStore` for in-session order

`ScreenMonitor` owns one `TaskbarPanel` per display, hides panels for displays in `hiddenDisplayIDs` or in a fullscreen Space, and drives auto-hide from mouse location.

## Actions and overlays

`WindowActions` raises, minimizes, unminimizes, closes, fullscreens, hides, quits, and “New Window” through `AXBridge` and `NSRunningApplication`. Primary click and middle-click are handled there. The thin Show desktop slice on the right of each bar calls `ShowDesktopController`, which minimizes every visible window on the current Spaces and restores that set on the next click.

Each `TaskbarPanel` owns a `StartMenuPanel` and `ThumbnailPopover`. Thumbnails use ScreenCaptureKit (`ThumbnailService`) only when Screen Recording was already granted at process start (`PermissionsManager.screenRecordingTrusted`).

`OverlapResizer` optionally shrinks windows whose Cocoa frames intersect the bar, skipping fullscreen/minimized/hidden windows, a bundle skip list, and PIDs that failed verification twice.

`DockBadgeReader` reads badge strings from Dock via Accessibility on a 2 s timer.

## Persistence

All of these are keys in `UserDefaults.standard`:

| Key | Contents |
| --- | --- |
| `omnibar.settings.v1` | JSON `AppSettings` |
| `omnibar.pins.v1` | pinned bundle IDs, order preserved |
| `omnibar.blacklist.v1` | blacklisted bundle IDs |
| `omnibar.recents.v1` | recent-launch bundle IDs |
| `omnibar.dock.backup.v1` | Dock autohide, delay, time-modifier, and orientation backup while fully hidden |

`OrderStore` is memory-only. `SettingsStore.resetToDefaults()` keeps the current launch-at-login value, writes default settings, reverts Dock, and clears order.

## Private and privileged APIs

| Area | Mechanism |
| --- | --- |
| Window titles, raise/minimize/close/fullscreen | Accessibility (`AXUIElement`) |
| Window frames, on-screen set, layers | `CGWindowListCopyWindowInfo` |
| Spaces and fullscreen Spaces | SkyLight (`dlopen` of `CGS*` / `SLS*` symbols) |
| Mission Control Dock strip | `CGSSetWindowLevel` on Dock windows |
| Live thumbnails | ScreenCaptureKit |
| Launch at login | `SMAppService.mainApp` |

The app is not sandboxed (`ENABLE_APP_SANDBOX` is NO; entitlements file is empty). Hardened Runtime is on.

## Tests

`OmnibarTests` covers stores, list logic, geometry, paging, settings decode, onboarding/TCC helpers, thumbnails, show-desktop, overlap, and related pure helpers. Tests load the app as `TEST_HOST`. `AppDelegate` returns immediately when `XCTestCase` is present so the live tracker does not start inside the test host.
