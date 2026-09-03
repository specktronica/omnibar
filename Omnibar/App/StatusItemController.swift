import AppKit

final class StatusItemController {
    private var item: NSStatusItem?

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = BrandIcon.image(pointSize: 18)
            button.image?.isTemplate = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.image?.accessibilityDescription = "Omnibar"
            button.toolTip = "Omnibar"
        }
        item.menu = buildMenu()
        self.item = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(Target.settings), keyEquivalent: ",")
        settings.target = Target.shared
        menu.addItem(settings)
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

        @objc func quit() {
            NSApp.terminate(nil)
        }
    }
}
