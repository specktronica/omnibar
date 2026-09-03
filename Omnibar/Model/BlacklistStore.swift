import Foundation
import Observation

@Observable
final class BlacklistStore {
    static let shared = BlacklistStore()

    static let defaultsKey = "omnibar.blacklist.v1"
    private let defaults: UserDefaults
    private(set) var bundleIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let array = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        bundleIDs = Set(array)
    }

    func contains(_ bundleID: String) -> Bool {
        bundleIDs.contains(bundleID)
    }

    func add(_ bundleID: String) {
        guard !bundleID.isEmpty else { return }
        bundleIDs.insert(bundleID)
        persist()
    }

    func remove(_ bundleID: String) {
        bundleIDs.remove(bundleID)
        persist()
    }

    func replace(_ ids: [String]) {
        bundleIDs = Set(ids)
        persist()
    }

    private func persist() {
        defaults.set(Array(bundleIDs).sorted(), forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: .omnibarBlacklistDidChange, object: nil)
    }
}
