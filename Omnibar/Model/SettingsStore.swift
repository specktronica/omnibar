import Foundation
import Observation

@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    static let defaultsKey = "omnibar.settings.v1"
    private let defaults: UserDefaults
    private let syncLoginItem: (Bool) -> Void
    private let applyDockFromSettings: () -> Void
    private let revertDock: () -> Void
    private var isLoading = false

    var settings: AppSettings {
        didSet {
            guard !isLoading, oldValue != settings else { return }
            persist()
            NotificationCenter.default.post(name: .omnibarSettingsDidChange, object: nil)
            if oldValue.launchAtLogin != settings.launchAtLogin {
                syncLoginItem(settings.launchAtLogin)
            }
            if oldValue.fullyHideDock != settings.fullyHideDock {
                applyDockFromSettings()
            }
        }
    }

    init(
        defaults: UserDefaults = .standard,
        syncLoginItem: @escaping (Bool) -> Void = { LoginItem.sync(enabled: $0) },
        applyDockFromSettings: @escaping () -> Void = { DockManager.shared.applyFromSettings() },
        revertDock: @escaping () -> Void = { DockManager.shared.revertIfNeeded() }
    ) {
        self.defaults = defaults
        self.syncLoginItem = syncLoginItem
        self.applyDockFromSettings = applyDockFromSettings
        self.revertDock = revertDock
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    func load() {
        isLoading = true
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }
        isLoading = false
        syncLoginItem(settings.launchAtLogin)
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
    }

    func resetToDefaults() {
        let launch = settings.launchAtLogin
        var next = AppSettings.default
        next.launchAtLogin = launch
        settings = next
        revertDock()
        OrderStore.shared.reset()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
