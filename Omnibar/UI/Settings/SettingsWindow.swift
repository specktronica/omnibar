import AppKit
import SwiftUI

enum SettingsWindow {
    static var controller: NSWindowController?

    static func show() {
        if let controller {
            NSApp.activate()
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsRootView()
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Omnibar Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 640, height: 520))
        window.center()
        let controller = NSWindowController(window: window)
        Self.controller = controller
        NSApp.activate()
        controller.showWindow(nil)
    }
}

struct SettingsRootView: View {
    @Bindable var store = SettingsStore.shared

    var body: some View {
        TabView {
            GeneralPane(settings: $store.settings).tabItem { Label("General", systemImage: "gearshape") }
            AppearancePane(settings: $store.settings).tabItem { Label("Appearance", systemImage: "paintbrush") }
            BehaviorPane(settings: $store.settings).tabItem { Label("Behavior", systemImage: "pointer.arrow.click") }
            ThumbnailsPane(settings: $store.settings).tabItem { Label("Thumbnails", systemImage: "rectangle.on.rectangle") }
            DisplaysPane(settings: $store.settings).tabItem { Label("Displays", systemImage: "display.2") }
            StartMenuPane(settings: $store.settings).tabItem { Label("Start Menu", systemImage: "square.grid.2x2") }
            AppsPane().tabItem { Label("Apps", systemImage: "app.badge") }
            AdvancedPane(settings: $store.settings).tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 460)
    }
}

private struct GeneralPane: View {
    @Binding var settings: AppSettings
    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            Toggle("Fully hide Dock", isOn: $settings.fullyHideDock)
            Toggle("Auto-hide Taskbar", isOn: $settings.autoHide)
            Picker("Start button", selection: $settings.startButtonAction) {
                ForEach(StartButtonAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearancePane: View {
    @Binding var settings: AppSettings
    var body: some View {
        Form {
            Toggle("Match system appearance", isOn: $settings.followSystemAppearance)
            Toggle("Force dark mode", isOn: $settings.forceDarkMode)
                .disabled(settings.followSystemAppearance)
            Slider(value: $settings.transparency, in: 0...1) {
                Text("Transparency")
            }
            Text(settings.transparency < 0.05 ? "Opaque (legacy look)" : "Live preview of the desktop behind the bar")
                .foregroundStyle(.secondary)
                .font(.caption)
            Slider(value: $settings.taskbarHeight, in: 28...64, step: 1) {
                Text("Taskbar size")
            }
            Slider(value: $settings.fontSize, in: 10...16, step: 1) {
                Text("Font size")
            }
            Toggle("Hide window titles (icons only)", isOn: $settings.iconOnly)
        }
        .formStyle(.grouped)
    }
}

private struct BehaviorPane: View {
    @Binding var settings: AppSettings
    var body: some View {
        Form {
            Toggle("Group windows by application", isOn: $settings.groupByApplication)
            Toggle("Show tabs as individual items", isOn: $settings.showTabsAsItems)
            Toggle("Indicate minimized or hidden windows", isOn: $settings.indicateMinimizedHidden)
            Toggle("Hide the app instead of minimizing on click", isOn: $settings.hideOnClickInsteadOfMinimize)
            Toggle("Allow drag and drop reordering", isOn: $settings.allowDragReorder)
            Toggle("Keep task order when a window changes Space", isOn: $settings.keepOrderAcrossSpaceChange)
            Toggle("Auto-resize windows that overlap Taskbar", isOn: $settings.autoResizeOverlapping)
        }
        .formStyle(.grouped)
    }
}

private struct ThumbnailsPane: View {
    @Binding var settings: AppSettings
    var body: some View {
        Form {
            Slider(value: $settings.thumbnailDelay, in: 0...1.5, step: 0.05) {
                Text("Hover delay")
            }
            Slider(value: $settings.thumbnailSize, in: 140...420, step: 10) {
                Text("Thumbnail size")
            }
            Toggle("Show window title in thumbnail", isOn: $settings.showTitleInThumbnail)
            Text("Screen Recording is optional. Without it, Omnibar shows the app icon instead of a live preview.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Request Screen Recording…") {
                _ = PermissionsManager.shared.promptScreenRecording()
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplaysPane: View {
    @Binding var settings: AppSettings
    var body: some View {
        Form {
            Toggle("Show Taskbar only on the main display", isOn: $settings.mainDisplayOnly)
            Toggle("Show windows from all screens on every Taskbar", isOn: $settings.showWindowsFromAllScreens)
            Section("Displays") {
                ForEach(NSScreen.screens, id: \.displayID) { screen in
                    Toggle(screen.localizedName, isOn: displayVisibleBinding(screen.displayID))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func displayVisibleBinding(_ id: CGDirectDisplayID) -> Binding<Bool> {
        Binding(
            get: { !settings.hiddenDisplayIDs.contains(id) },
            set: { visible in
                if visible {
                    settings.hiddenDisplayIDs.removeAll { $0 == id }
                } else if !settings.hiddenDisplayIDs.contains(id) {
                    settings.hiddenDisplayIDs.append(id)
                }
            }
        )
    }
}

private struct StartMenuPane: View {
    @Binding var settings: AppSettings
    var body: some View {
        Form {
            Picker("Start button action", selection: $settings.startButtonAction) {
                ForEach(StartButtonAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            Stepper("Recent apps: \(settings.recentAppsLimit)", value: $settings.recentAppsLimit, in: 3...20)
            Text("Right-click the Start button on the Taskbar to change the default action.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AppsPane: View {
    @Bindable var pins = PinStore.shared
    @Bindable var blacklist = BlacklistStore.shared
    @State private var pinDraft = ""
    @State private var blacklistDraft = ""

    var body: some View {
        Form {
            Section("Pinned apps") {
                ForEach(pins.pinnedBundleIDs, id: \.self) { id in
                    HStack {
                        Text(IconCache.appName(for: id))
                        Spacer()
                        Button("Remove") { pins.unpin(id) }
                    }
                }
                HStack {
                    TextField("Bundle identifier", text: $pinDraft)
                    Button("Pin") {
                        pins.pin(pinDraft.trimmingCharacters(in: .whitespaces))
                        pinDraft = ""
                    }
                }
            }
            Section("Blacklist") {
                ForEach(Array(blacklist.bundleIDs).sorted(), id: \.self) { id in
                    HStack {
                        Text(IconCache.appName(for: id))
                        Spacer()
                        Button("Remove") { blacklist.remove(id) }
                    }
                }
                HStack {
                    TextField("Bundle identifier", text: $blacklistDraft)
                    Button("Add") {
                        blacklist.add(blacklistDraft.trimmingCharacters(in: .whitespaces))
                        blacklistDraft = ""
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedPane: View {
    @Binding var settings: AppSettings
    @State private var skipDraft = ""

    var body: some View {
        Form {
            Slider(value: $settings.pollInterval, in: 0.5...4, step: 0.1) {
                Text("Window list refresh (seconds)")
            }
            Section("Overlap resize skip list") {
                ForEach(settings.overlapSkipBundleIDs, id: \.self) { id in
                    HStack {
                        Text(id)
                        Spacer()
                        Button("Remove") {
                            settings.overlapSkipBundleIDs.removeAll { $0 == id }
                        }
                    }
                }
                HStack {
                    TextField("Bundle identifier", text: $skipDraft)
                    Button("Add") {
                        let value = skipDraft.trimmingCharacters(in: .whitespaces)
                        if !value.isEmpty, !settings.overlapSkipBundleIDs.contains(value) {
                            settings.overlapSkipBundleIDs.append(value)
                        }
                        skipDraft = ""
                    }
                }
            }
            Button("Reset to defaults") {
                SettingsStore.shared.resetToDefaults()
                DockManager.shared.revertIfNeeded()
            }
        }
        .formStyle(.grouped)
    }
}
