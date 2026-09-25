# Usage

Omnibar is a bottom-of-screen taskbar. It lists windows on the current Space (minimized windows stay on their last screen), optional pinned apps, and a Start button. **Show windows from all Spaces** also lists windows on other desktops. Tiles are grouped by application by default. There is no Dock icon while it is running, except during first-run onboarding.

## First launch

If Accessibility is not granted, an onboarding window appears. Continue stays disabled until Accessibility is on. The taskbar appears only after you click Continue (or close the window). Screen Recording and “Hide the Dock on the right” are optional on that screen. Granting Screen Recording in this session does not enable live thumbnails until Omnibar relaunches: the row marks as granted, the primary button becomes Restart (that button is enabled even if Accessibility is still off), and Enable Screen Recording stays available until the new process starts.

After that, Omnibar lives in the menu bar. The extra’s menu is **Settings…** (⌘,), **Tip Omnibar…**, and **Quit Omnibar** (⌘Q). **Tip Omnibar…** opens the Ko-fi page in a browser. Clicking the app again while it is already running opens Settings, as long as Accessibility is granted.

## Taskbar

Each display gets its own bar unless Settings hide that display or restrict the bar to the main display. The bar is suppressed on a display that is in a fullscreen Space.

| Action | Result |
| --- | --- |
| Click a tile | Raise that window (or launch a pinned app with no open windows) |
| Click the active tile | Minimize the window, or hide the app if that setting is on |
| Middle-click a tile | New Window (app menu item “New Window” / “New Document” / “New”, else ⌘N; launches the app if it is not running) |
| Right-click a tile | Window menu (see below) |
| Hover a tile | Thumbnail popover after the configured delay |
| Drag a tile | Reorder, when drag-and-drop reordering is enabled |
| Click the Start button | Start Menu, Launchpad, or Spotlight (configured action) |
| Right-click the Start button | Choose the Start button action |
| Control + Option | Close the Start Menu if it is open. Press and release to open it on the display under the pointer |
| Click the Show desktop slice (far right) | Minimize all windows on the current Spaces; click again to restore |

In icons-only or grouped mode, a compact tile draws a blue running mark under the icon (wider when that window is active on this Space). A grouped app with two windows draws two dots, and three or more windows draw three. A window on another Space draws its mark as a ring, and windows on this Space are drawn first. When a group has more than three windows and any of them is on another Space, the last dot stays a ring. The tile tooltip adds “Another Space” for the window it names. Clicking a grouped tile raises a non-minimized window on the current Space when there is one, otherwise a window on another Space, or minimizes/hides if one of the group is already active. A click on a window in another Space switches to that Space.

### Window menu

Right-click a tile:

- **Taskbar** submenu: Settings, hide the bar on this display, show windows from all screens, show windows from all Spaces, reset settings, quit Omnibar
- **Keep in Taskbar** — pin by bundle ID (stays on the bar when the app has no windows)
- **New Window**, **Hide**, **Add to Blacklist**, **Quit**
- **Fullscreen**, **Minimize**, **Close**
- When grouped with more than one window, each window title is listed so you can raise a specific one. A window on another Space has “Another Space” after its title

### Hover thumbnails

The popover shows up to three cards at a time and pages when a group has more. Live captures need Screen Recording; otherwise the card uses the app icon. Cards have close / minimize / zoom (Option or a fullscreen window uses fullscreen instead of zoom). A card for a window on another Space says “Another Space” in the title row, including when thumbnail titles are off. Hovering a card temporarily raises that window when it is already on screen. A minimized, hidden, or other-Space window stays that way until the card is clicked. Leaving the popover restores the previous front window unless you clicked a card.

## Start Menu

The Start Menu is a panel above the Start button: search field, A–Z application list, **Pinned Apps** grid (same pin list as the taskbar), and **Recent Apps**.

Press Control + Option to close the menu. Press those keys and release them, without another key, click, or scroll, to open it on the display under the pointer. If that bar is hidden or the display is in a fullscreen Space, the menu opens on the main display's bar, then any bar that is showing. Holding Control + Option and pressing an arrow still tiles. Closing with this shortcut returns the keyboard to the app that was in front.

Search filters by app name (case-insensitive substring). Up/Down move the highlight in the app list (including while filtering); Enter launches the highlighted app. Launching an app records it in recents, capped by Settings → Start Menu (3–20, default 10). Omnibar itself is not added to recents.

The catalog is scanned from `/Applications`, `/System/Applications`, `/System/Applications/Utilities`, and `~/Applications`.

If the Start button is set to Launchpad and Launchpad is missing or fails to open, Omnibar posts ⌘Space (Spotlight) instead.

## Window tiling

Tiling moves and resizes standard windows of other apps through Accessibility. Tiles fill the display's usable area: the screen minus the menu bar, minus the Taskbar strip on displays where Omnibar shows a bar. Dialogs, sheets, fullscreen windows, minimized windows, Omnibar's own windows, and windows whose size cannot be set are ignored.

### Keyboard

Default shortcuts are Control + Option + Arrow. The modifier set is configurable in Settings → Tiling.

| Shortcut | Result |
| --- | --- |
| ⌃⌥→ | Right half. Press again: top-right quarter, then bottom-right quarter, then right half. From a left quarter, moves to the right quarter in the same row |
| ⌃⌥← | Left half. Press again: top-left quarter, then bottom-left quarter, then left half. From a right quarter, moves to the left quarter in the same row |
| ⌃⌥↑ | Top half. Press again: fill the usable area, then top half. From a bottom quarter, moves to the top quarter in the same column |
| ⌃⌥↓ | Bottom half. Press again: fill the usable area, then bottom half. From a top quarter, moves to the bottom quarter in the same column |

Omnibar treats a press as a repeat when the focused window's frame is within 8 points of the last tile. If the app refused the size (a minimum-size clamp), the frame Omnibar observed after the last tile is used instead. Moving or resizing the window by hand restarts the cycle at the half.

Choosing **Control** alone collides with Mission Control itself (⌃↑), “Application windows” (⌃↓), and “Move left a space” / “Move right a space”. macOS takes those keys first, so tiling does nothing until you turn them off in System Settings → Keyboard → Keyboard Shortcuts → Mission Control. Settings → Tiling shows this note and a button to that pane.

If another app has already registered the same combination, Omnibar logs the conflict and leaves the shortcut unregistered.

## Settings

Open from the menu extra, the taskbar **Taskbar → Settings…** item, or by reopening the app.

| Pane | Controls |
| --- | --- |
| General | Launch at login, hide the Dock on the right, auto-hide taskbar, Start button action |
| Appearance | Match system appearance or force dark, transparency, bar height, font size, icons-only, Start logo presets and per-lobe colors |
| Behavior | Group by application, show tabs as items, indicate minimized/hidden, hide instead of minimize on click, Show desktop button, drag reorder, keep order across Space changes, auto-resize overlapping windows |
| Tiling | Keyboard tiling on/off, modifier set (Control + Option, Control, Control + Command, Control + Option + Command), current shortcuts, Mission Control note when Control alone is selected |
| Thumbnails | Hover delay, size, title in thumbnail, request Screen Recording |
| Displays | Main display only, show windows from all screens, show windows from all Spaces, per-display visibility |
| Start Menu | Start button action, recent-apps count, Control + Option shortcut |
| Apps | Pinned bundle IDs and blacklist |
| Advanced | Window-list poll interval, overlap-resize skip list, reset to defaults |
| About | Version, Tip on Ko-fi, copy Bitcoin and Ethereum addresses |

Reset to defaults restores `AppSettings.default` except **Launch at login**, which is left as-is. It also reverts Dock changes Omnibar made and clears in-session tile order.

### Defaults

| Setting | Default |
| --- | --- |
| Match system appearance | on |
| Force dark mode | off (ignored while matching system appearance) |
| Transparency | 0.55 |
| Taskbar height | 50 pt (slider 28–64) |
| Font size | 12 (slider 10–16) |
| Hide window titles (icons only) | off |
| Group by application | on |
| Show tabs as individual items | on |
| Indicate minimized or hidden | on |
| Hide instead of minimize on click | off |
| Show desktop button | on |
| Thumbnail delay | 0.4 s (0–1.5) |
| Thumbnail size | 240 (140–420) |
| Show window title in thumbnail | off |
| Show windows from all screens | off |
| Show windows from all Spaces | off |
| Main display only | off |
| Auto-resize overlapping windows | on |
| Keep order across Space change | on |
| Drag reorder | on |
| Auto-hide taskbar | off |
| Window list refresh | 1.5 s (0.5–4) |
| Hide the Dock on the right | on |
| Launch at login | on |
| Start button | Start Menu |
| Recent apps | 10 |
| Start logo | Classic |
| Keyboard tiling | on |
| Tiling modifiers | Control + Option |

Logo presets: Classic, Sunset, Ocean, Forest, Candy, Neon, Mono. Each of the four lobes can be recolored.

### Dock position

When **Hide the Dock on the right** is on (the default, including the first launch after install), Omnibar backs up `com.apple.dock` autohide, delay, time-modifier, and orientation, turns autohide on, sets orientation to `right`, and restarts the Dock. The Dock becomes a vertical Dock on the right edge and stays hidden until the pointer reaches that edge. A saved delay of 1000 seconds, left by older builds that fully hid the Dock, is reset so it can appear. The backup is restored when you turn the setting off, reset settings, or quit Omnibar. A force-quit can leave the Dock on the right edge and hidden; launch Omnibar and turn the setting off, or run `make remove`. `make remove` still recognizes the older fully-hidden signature (`autohide-delay` 1000 and orientation `top`). A Homebrew `--zap` while Omnibar is not running can delete the backup without restoring it.

### Auto-hide

The bar moves off the bottom of the display (2 points remain visible) when the cursor leaves it, the Start Menu, and the thumbnail. An open Start Menu keeps its bar visible until the menu closes. A 3-point hot strip along the bottom of the taskbar, or moving onto the bar, shows it again.

### Pins, blacklist, overlap skip

Pins, blacklist, and overlap-skip entries are bundle identifiers (for example `com.apple.Safari`). Blacklisted apps never appear as tiles. Overlap skip prevents auto-resize of that app’s windows. Pins that are running show as normal tiles; pins with no windows stay as launchers.

Settings, pins, blacklist, and recents are stored in the app’s `UserDefaults`. Tile order is session-only.
