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
        // Ten tab labels need about 700 pt before the tab bar truncates them.
        window.setContentSize(NSSize(width: 720, height: 620))
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
            TilingPane(settings: $store.settings).tabItem { Label("Tiling", systemImage: "rectangle.split.2x1") }
            ThumbnailsPane(settings: $store.settings).tabItem { Label("Thumbnails", systemImage: "rectangle.on.rectangle") }
            DisplaysPane(settings: $store.settings).tabItem { Label("Displays", systemImage: "display.2") }
            StartMenuPane(settings: $store.settings).tabItem { Label("Start Menu", systemImage: "square.grid.2x2") }
            AppsPane().tabItem { Label("Apps", systemImage: "app.badge") }
            AdvancedPane(settings: $store.settings).tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            AboutPane().tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 520)
        // Native NSSwitch uses controlAccentColor, which AppKit draws as
        // graphite when this accessory app's window is not key.
        .toggleStyle(PersistentSwitchToggleStyle())
        .environment(\.controlActiveState, .key)
    }
}

/// Switch that keeps the system accent while the settings window is inactive.
private struct PersistentSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            PersistentSwitch(isOn: configuration.$isOn)
        } label: {
            configuration.label
        }
    }
}

private struct PersistentSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? PersistentAccent.color : Color.primary.opacity(0.18))
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 1)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
            .animation(.easeInOut(duration: 0.12), value: isOn)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private enum PersistentAccent {
    static var color: Color { Color(nsColor: nsColor) }

    /// `controlAccentColor` is grayed when the window is inactive. Map the
    /// user's accent preference to a system color that does not desaturate.
    static var nsColor: NSColor {
        switch UserDefaults.standard.object(forKey: "AppleAccentColor") as? Int {
        case -1: .systemGray
        case 0: .systemRed
        case 1: .systemOrange
        case 2: .systemYellow
        case 3: .systemGreen
        case 4: .systemBlue
        case 5: .systemPurple
        case 6: .systemPink
        default: .systemBlue
        }
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
            StartLogoSection(settings: $settings)
        }
        .formStyle(.grouped)
    }
}

private struct StartLogoSection: View {
    @Binding var settings: AppSettings

    var body: some View {
        Section("Start button logo") {
            HStack(spacing: 14) {
                StartLogoPreview(palette: settings.startLogo, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(StartLogoTheme.matching(settings.startLogo)?.title ?? "Custom")
                    Text("Choose a preset, or set each lobe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(StartLogoTheme.allCases) { theme in
                    Button {
                        settings.startLogo = theme.palette
                    } label: {
                        StartLogoPreview(palette: theme.palette, size: 28)
                            .padding(5)
                            .background(presetBackground(theme))
                            .overlay(presetBorder(theme))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.title)
                    .accessibilityAddTraits(isSelected(theme) ? [.isSelected] : [])
                    .help(theme.title)
                }
                Spacer(minLength: 0)
            }
            ColorPicker("Left", selection: lobeBinding(\.left), supportsOpacity: false)
            ColorPicker("Top", selection: lobeBinding(\.top), supportsOpacity: false)
            ColorPicker("Right", selection: lobeBinding(\.right), supportsOpacity: false)
            ColorPicker("Bottom", selection: lobeBinding(\.bottom), supportsOpacity: false)
        }
    }

    private func isSelected(_ theme: StartLogoTheme) -> Bool {
        StartLogoTheme.matching(settings.startLogo) == theme
    }

    private func presetBackground(_ theme: StartLogoTheme) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected(theme) ? PersistentAccent.color.opacity(0.16) : Color.clear)
    }

    private func presetBorder(_ theme: StartLogoTheme) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(
                isSelected(theme) ? PersistentAccent.color : Color.secondary.opacity(0.22),
                lineWidth: isSelected(theme) ? 1.5 : 1
            )
    }

    private func lobeBinding(_ keyPath: WritableKeyPath<StartLogoPalette, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.startLogo[keyPath: keyPath].nsColor) },
            set: { newColor in
                var palette = settings.startLogo
                palette[keyPath: keyPath] = RGBAColor(nsColor: NSColor(newColor))
                settings.startLogo = palette
            }
        )
    }
}

private struct StartLogoPreview: View {
    var palette: StartLogoPalette
    var size: CGFloat

    var body: some View {
        Image(nsImage: BrandIcon.image(pointSize: size, palette: palette))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
            Toggle("Show desktop button on the right edge", isOn: $settings.showDesktopButton)
            Toggle("Allow drag and drop reordering", isOn: $settings.allowDragReorder)
            Toggle("Keep task order when a window changes Space", isOn: $settings.keepOrderAcrossSpaceChange)
            Toggle("Auto-resize windows that overlap Taskbar", isOn: $settings.autoResizeOverlapping)
        }
        .formStyle(.grouped)
    }
}

private struct TilingPane: View {
    @Binding var settings: AppSettings

    private static let keyboardShortcutsURL = URL(
        string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"
    )

    var body: some View {
        Form {
            Toggle("Tile the focused window with keyboard shortcuts", isOn: $settings.tilingShortcutsEnabled)
            Picker("Modifiers", selection: $settings.tilingModifiers) {
                ForEach(TilingModifiers.allCases) { modifiers in
                    Text(modifiers.title).tag(modifiers)
                }
            }
            .disabled(!settings.tilingShortcutsEnabled)
            LabeledContent("Tile left", value: "\(settings.tilingModifiers.symbol)←")
            LabeledContent("Tile right", value: "\(settings.tilingModifiers.symbol)→")
            LabeledContent("Tile up", value: "\(settings.tilingModifiers.symbol)↑")
            LabeledContent("Tile down", value: "\(settings.tilingModifiers.symbol)↓")
            Text("Left/right: press again to cycle half → top quarter → bottom quarter → half.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Up: press again to fill the usable area, then back to the top half.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Down: press again to fill the usable area, then back to the bottom half.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if settings.tilingModifiers.conflictsWithMissionControl {
                Text("Mission Control uses Control + Arrow and takes the key first. Turn off “Move left a space”, “Move right a space”, “Mission Control”, and “Application windows” under Keyboard Shortcuts → Mission Control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Keyboard Shortcuts…") {
                    if let url = Self.keyboardShortcutsURL {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
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

private struct AboutPane: View {
    @State private var copiedAddress: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Omnibar") {
                    Text(versionText)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Tip on Ko-fi") {
                    SupportLinks.openKoFi()
                }
                Text("Tips are optional and do not unlock features.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Crypto") {
                addressRow(title: "Bitcoin", address: SupportLinks.bitcoin)
                addressRow(title: "Ethereum", address: SupportLinks.ethereum)
            }
        }
        .formStyle(.grouped)
    }

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private func addressRow(title: String, address: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(address)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(copiedAddress == address ? "Copied" : "Copy") {
                SupportLinks.copy(address)
                copiedAddress = address
            }
        }
    }
}
