import AppKit
import SwiftUI

enum OnboardingWindow {
    static var controller: NSWindowController?

    static func show() {
        if controller == nil {
            let hosting = NSHostingController(rootView: PermissionsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Omnibar"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 460, height: 360))
            window.center()
            controller = NSWindowController(window: window)
        }
        NSApp.activate()
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
    }

    static func closeIfTrusted() {
        if PermissionsManager.shared.accessibilityTrusted {
            controller?.close()
        }
    }
}

struct PermissionsView: View {
    @State private var accessibility = PermissionsManager.shared.accessibilityTrusted
    @State private var screen = PermissionsManager.shared.screenRecordingTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Omnibar")
                .font(.title2.bold())
            Text("Omnibar is a Windows-style taskbar for macOS. Accessibility is required to list and switch windows. Screen Recording is optional and only used for live hover thumbnails.")
                .foregroundStyle(.secondary)
            permissionRow(
                title: "Accessibility",
                subtitle: "Required to read window titles and raise, minimize, or close windows.",
                granted: accessibility,
                actionTitle: "Enable Accessibility"
            ) {
                _ = PermissionsManager.shared.promptAccessibility()
                refresh()
            }
            permissionRow(
                title: "Screen Recording",
                subtitle: "Optional. Enables live window thumbnails on hover.",
                granted: screen,
                actionTitle: "Enable Screen Recording"
            ) {
                _ = PermissionsManager.shared.promptScreenRecording()
                refresh()
            }
            Spacer()
            HStack {
                Spacer()
                Button("Continue") {
                    OnboardingWindow.closeIfTrusted()
                    NotificationCenter.default.post(name: .omnibarPermissionsDidChange, object: nil)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!accessibility)
            }
        }
        .padding(24)
        .frame(width: 460, height: 340)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        PermissionsManager.shared.refresh()
        accessibility = PermissionsManager.shared.accessibilityTrusted
        screen = PermissionsManager.shared.screenRecordingTrusted
        if accessibility {
            OnboardingWindow.closeIfTrusted()
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
