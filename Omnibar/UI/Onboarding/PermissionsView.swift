import AppKit
import SwiftUI

enum OnboardingWindow {
    static var isShowing = false

    private static var controller: NSWindowController?
    private static let windowDelegate = OnboardingWindowDelegate()
    private static var suppressReopen = false
    private static var reopenSuppressWork: DispatchWorkItem?

    static var shouldIgnoreReopen: Bool { suppressReopen }

    static func show() {
        isShowing = true
        PermissionsManager.shared.startPolling()
        NSApp.setActivationPolicy(.regular)
        windowDelegate.startObservingSystemSettings()
        if controller == nil {
            let hosting = NSHostingController(rootView: PermissionsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Omnibar"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 460, height: 430))
            window.center()
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.canHide = false
            window.delegate = windowDelegate
            controller = NSWindowController(window: window)
        }
        reveal()
    }

    static func reveal() {
        guard isShowing, let window = controller?.window else { return }
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }
        NSApp.setActivationPolicy(.regular)
        controller?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            NSApp.activate()
        }
        // LSUIElement apps are not activated at launch, and cooperative
        // activation on macOS 14+ can be refused while another app is active.
        // makeKeyAndOrderFront keeps an inactive app's window behind the active
        // app, so force it above other apps' windows as the last step.
        window.orderFrontRegardless()
        PermissionsManager.shared.refresh()
    }

    static func dismiss() {
        guard isShowing else { return }
        controller?.window?.canHide = true
        controller?.close()
    }

    static func finish() {
        guard isShowing else { return }
        isShowing = false
        PermissionsManager.shared.stopPolling()
        beginReopenSuppression()
        NSApp.setActivationPolicy(.accessory)
        if PermissionsManager.shared.accessibilityTrusted {
            NotificationCenter.default.post(name: .omnibarPermissionsDidChange, object: nil)
        }
    }

    private static func beginReopenSuppression() {
        suppressReopen = true
        reopenSuppressWork?.cancel()
        let work = DispatchWorkItem { suppressReopen = false }
        reopenSuppressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    static func handleSystemSettingsDidQuit() {
        guard isShowing else { return }
        reveal()
    }
}

private final class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    private var workspaceTokens: [NSObjectProtocol] = []
    private static let systemSettingsBundleIDs: Set<String> = [
        "com.apple.systempreferences",
        "com.apple.Preferences"
    ]

    func startObservingSystemSettings() {
        guard workspaceTokens.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        // Losing focus only triggers a permission re-check. Activating Omnibar
        // on every deactivate would steal focus when the user switches to an
        // unrelated app. Quitting System Settings brings the window back.
        let handlers: [(Notification.Name, @MainActor () -> Void)] = [
            (NSWorkspace.didDeactivateApplicationNotification, { PermissionsManager.shared.refresh() }),
            (NSWorkspace.didTerminateApplicationNotification, { OnboardingWindow.handleSystemSettingsDidQuit() })
        ]
        for (name, handler) in handlers {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { notification in
                let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .bundleIdentifier
                Task { @MainActor in
                    guard let bundleID, Self.systemSettingsBundleIDs.contains(bundleID) else { return }
                    handler()
                }
            }
            workspaceTokens.append(token)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !OnboardingWindow.isShowing { return true }
        return NSApp.isActive
    }

    func windowWillClose(_ notification: Notification) {
        OnboardingWindow.finish()
    }
}

struct PermissionsView: View {
    private let permissions = PermissionsManager.shared
    @Bindable private var store = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Omnibar")
                .font(.title2.bold())
            Text("Omnibar is a Windows-style taskbar for macOS. Accessibility is required to list and switch windows. Screen Recording is optional and only used for live hover thumbnails.")
                .foregroundStyle(.secondary)
            permissionRow(
                title: "Accessibility",
                subtitle: "Required to read window titles and raise, minimize, or close windows.",
                granted: permissions.accessibilityTrusted,
                actionTitle: "Enable Accessibility"
            ) {
                _ = PermissionsManager.shared.promptAccessibility()
            }
            permissionRow(
                title: "Screen Recording",
                subtitle: "Optional. Enables live window thumbnails on hover.",
                granted: permissions.screenRecordingTrusted,
                actionTitle: "Enable Screen Recording"
            ) {
                _ = PermissionsManager.shared.promptScreenRecording()
            }
            HStack(alignment: .top) {
                Image(systemName: store.settings.fullyHideDock ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(store.settings.fullyHideDock ? .green : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hide the macOS Dock").font(.headline)
                    Text("Keeps the system Dock fully hidden while Omnibar is running so the two bars do not overlap. The Dock is restored when you quit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Hide the macOS Dock", isOn: $store.settings.fullyHideDock)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            Spacer()
            HStack {
                Spacer()
                Button("Continue") {
                    OnboardingWindow.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!permissions.accessibilityTrusted)
            }
        }
        .padding(24)
        .frame(width: 460, height: 410)
        .onAppear {
            PermissionsManager.shared.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            PermissionsManager.shared.refresh()
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button(actionTitle, action: action)
            }
        }
    }
}
