import Foundation
import Observation

@Observable
final class PinStore {
    static let shared = PinStore()

    static let defaultsKey = "omnibar.pins.v1"
    private let defaults: UserDefaults
    private(set) var pinnedBundleIDs: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinnedBundleIDs = defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }

    func isPinned(_ bundleID: String) -> Bool {
        pinnedBundleIDs.contains(bundleID)
    }

    func toggle(_ bundleID: String) {
        if isPinned(bundleID) {
            unpin(bundleID)
        } else {
            pin(bundleID)
        }
    }

    func pin(_ bundleID: String) {
        guard !bundleID.isEmpty, !isPinned(bundleID) else { return }
        pinnedBundleIDs.append(bundleID)
        persist()
    }

    func unpin(_ bundleID: String) {
        pinnedBundleIDs.removeAll { $0 == bundleID }
        persist()
    }

    func move(id: String, to index: Int) {
        guard let from = pinnedBundleIDs.firstIndex(of: id) else { return }
        var ids = pinnedBundleIDs
        let item = ids.remove(at: from)
        let clamped = max(0, min(index, ids.count))
        ids.insert(item, at: clamped)
        pinnedBundleIDs = ids
        persist()
    }

    func replace(_ ids: [String]) {
        pinnedBundleIDs = ids
        persist()
    }

    private func persist() {
        defaults.set(pinnedBundleIDs, forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: .omnibarPinsDidChange, object: nil)
    }
}
