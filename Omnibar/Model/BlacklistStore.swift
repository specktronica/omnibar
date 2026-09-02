import Foundation
import Observation

@Observable
final class BlacklistStore {
    static let shared = BlacklistStore()

    private let defaultsKey = "omnibar.blacklist.v1"
    private(set) var bundleIDs: Set<String>

    init() {
        let array = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
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
        UserDefaults.standard.set(Array(bundleIDs).sorted(), forKey: defaultsKey)
        NotificationCenter.default.post(name: .omnibarBlacklistDidChange, object: nil)
    }
}
