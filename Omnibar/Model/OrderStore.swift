import Foundation

final class OrderStore {
    static let shared = OrderStore()

    private(set) var order: [String] = []

    func reset() {
        order.removeAll()
    }

    func record(
        keys: [String],
        keepAcrossSpaceChange: Bool,
        appearing: Set<String>,
        disappearing: Set<String>
    ) {
        for key in keys where !order.contains(key) {
            order.append(key)
        }

        if !keepAcrossSpaceChange {
            for key in keys where appearing.contains(key) {
                order.removeAll { $0 == key }
                order.append(key)
            }
            order.removeAll { disappearing.contains($0) }
        } else if order.count > 400 {
            let live = Set(keys)
            order.removeAll { disappearing.contains($0) && !live.contains($0) }
        }
    }

    func sorted<T>(_ items: [T], key: (T) -> String) -> [T] {
        var index: [String: Int] = [:]
        index.reserveCapacity(order.count)
        for (i, k) in order.enumerated() where index[k] == nil {
            index[k] = i
        }
        return items.sorted { a, b in
            let ka = key(a)
            let kb = key(b)
            let ia = index[ka] ?? Int.max
            let ib = index[kb] ?? Int.max
            if ia != ib { return ia < ib }
            return ka < kb
        }
    }

    func move(id: String, before target: String?) {
        order.removeAll { $0 == id }
        if let target, let idx = order.firstIndex(of: target) {
            order.insert(id, at: idx)
        } else {
            order.append(id)
        }
    }

    func move(id: String, to index: Int) {
        order.removeAll { $0 == id }
        let clamped = max(0, min(index, order.count))
        order.insert(id, at: clamped)
    }

    func replace(_ keys: [String]) {
        order = keys
    }
}
