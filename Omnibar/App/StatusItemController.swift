import AppKit
import Foundation

final class StatusItemController {
    private var item: NSStatusItem?

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: "Omnibar")
            button.toolTip = "Omnibar"
        }
        item.menu = buildMenu()
        self.item = item
        NotificationCenter.default.addObserver(
            forName: .omnibarSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.item?.menu = self?.buildMenu()
            }
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(Target.settings), keyEquivalent: ",")
        settings.target = Target.shared
        menu.addItem(settings)
        let dock = NSMenuItem(title: "Fully Hide Dock", action: #selector(Target.toggleDock), keyEquivalent: "")
        dock.state = SettingsStore.shared.settings.fullyHideDock ? .on : .off
        dock.target = Target.shared
        menu.addItem(dock)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Omnibar", action: #selector(Target.quit), keyEquivalent: "q")
        quit.target = Target.shared
        menu.addItem(quit)
        return menu
    }

    final class Target: NSObject {
        static let shared = Target()

        @objc func settings() {
            SettingsWindow.show()
        }

        @objc func toggleDock() {
            SettingsStore.shared.update { $0.fullyHideDock.toggle() }
        }

        @objc func quit() {
            NSApp.terminate(nil)
        }
    }
}
