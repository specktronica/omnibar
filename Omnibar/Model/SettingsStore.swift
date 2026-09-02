import Foundation
import Observation

@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaultsKey = "omnibar.settings.v1"
    private var isLoading = false

    var settings: AppSettings {
        didSet {
            guard !isLoading, oldValue != settings else { return }
            persist()
            NotificationCenter.default.post(name: .omnibarSettingsDidChange, object: nil)
            if oldValue.launchAtLogin != settings.launchAtLogin {
                LoginItem.sync(enabled: settings.launchAtLogin)
            }
            if oldValue.fullyHideDock != settings.fullyHideDock {
                DockManager.shared.applyFromSettings()
            }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "omnibar.settings.v1"),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    func load() {
        isLoading = true
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }
        isLoading = false
        LoginItem.sync(enabled: settings.launchAtLogin)
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
    }

    func resetToDefaults() {
        let launch = settings.launchAtLogin
        settings = .default
        settings.launchAtLogin = launch
        DockManager.shared.revertIfNeeded()
        OrderStore.shared.reset()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
