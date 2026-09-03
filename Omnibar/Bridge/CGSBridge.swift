import CoreGraphics
import Foundation

typealias CGSConnectionID = Int32
typealias CGSSpaceID = UInt64

nonisolated protocol SpacesProviding: AnyObject, Sendable {
    func currentSpace(forDisplay displayID: CGDirectDisplayID) -> UInt64?
    func isFullscreenSpace(_ space: UInt64) -> Bool
    func spaces(forWindowIDs ids: [CGWindowID]) -> [CGWindowID: [UInt64]]
    func displaySpaceState(displayIDs: [CGDirectDisplayID]) -> (
        current: [CGDirectDisplayID: UInt64],
        fullscreen: Set<CGDirectDisplayID>
    )
}

nonisolated final class CGSBridge: SpacesProviding, Sendable {
    static let shared = CGSBridge()

    private typealias MainConnectionProc = @convention(c) () -> CGSConnectionID
    private typealias CopyManagedDisplaySpacesProc = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsProc = @convention(c) (CGSConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias ManagedDisplayGetCurrentSpaceProc = @convention(c) (CGSConnectionID, CFString) -> CGSSpaceID
    private typealias SpaceGetTypeProc = @convention(c) (CGSConnectionID, CGSSpaceID) -> Int32

    private let mainConnection: MainConnectionProc?
    private let copyManagedDisplaySpaces: CopyManagedDisplaySpacesProc?
    private let copySpacesForWindows: CopySpacesForWindowsProc?
    private let managedDisplayGetCurrentSpace: ManagedDisplayGetCurrentSpaceProc?
    private let spaceGetType: SpaceGetTypeProc?
    private let connection: CGSConnectionID

    private static let allSpacesSelector: Int32 = 7
    private static let fullscreenSpaceType: Int32 = 4

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: T.self)
        }
        mainConnection = load("CGSMainConnectionID", as: MainConnectionProc.self)
            ?? load("SLSMainConnectionID", as: MainConnectionProc.self)
        copyManagedDisplaySpaces = load("CGSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpacesProc.self)
            ?? load("SLSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpacesProc.self)
        copySpacesForWindows = load("CGSCopySpacesForWindows", as: CopySpacesForWindowsProc.self)
            ?? load("SLSCopySpacesForWindows", as: CopySpacesForWindowsProc.self)
        managedDisplayGetCurrentSpace = load("CGSManagedDisplayGetCurrentSpace", as: ManagedDisplayGetCurrentSpaceProc.self)
            ?? load("SLSManagedDisplayGetCurrentSpace", as: ManagedDisplayGetCurrentSpaceProc.self)
        spaceGetType = load("CGSSpaceGetType", as: SpaceGetTypeProc.self)
            ?? load("SLSSpaceGetType", as: SpaceGetTypeProc.self)
        connection = mainConnection?() ?? 0
    }

    func currentSpace(forDisplay displayID: CGDirectDisplayID) -> UInt64? {
        if let parsed = managedSpaces(), let match = parsed.first(where: { $0.displayID == displayID }) {
            return match.currentSpace
        }
        if let uuid = displayUUIDString(displayID), let proc = managedDisplayGetCurrentSpace {
            let space = proc(connection, uuid as CFString)
            return space == 0 ? nil : UInt64(space)
        }
        return nil
    }

    func isFullscreenSpace(_ space: UInt64) -> Bool {
        if let parsed = managedSpaces() {
            for display in parsed {
                if display.currentSpace == space {
                    return display.currentType == Self.fullscreenSpaceType
                }
                if let type = display.spaceTypes[space] {
                    return type == Self.fullscreenSpaceType
                }
            }
        }
        if let proc = spaceGetType {
            return proc(connection, CGSSpaceID(space)) == Self.fullscreenSpaceType
        }
        return false
    }

    func displaySpaceState(displayIDs: [CGDirectDisplayID]) -> (
        current: [CGDirectDisplayID: UInt64],
        fullscreen: Set<CGDirectDisplayID>
    ) {
        var current: [CGDirectDisplayID: UInt64] = [:]
        var fullscreen: Set<CGDirectDisplayID> = []
        if let parsed = managedSpaces() {
            for displayID in displayIDs {
                guard let match = parsed.first(where: { $0.displayID == displayID }) else { continue }
                current[displayID] = match.currentSpace
                let type = match.spaceTypes[match.currentSpace] ?? match.currentType
                if type == Self.fullscreenSpaceType {
                    fullscreen.insert(displayID)
                }
            }
            return (current, fullscreen)
        }
        for displayID in displayIDs {
            if let space = currentSpace(forDisplay: displayID) {
                current[displayID] = space
                if isFullscreenSpace(space) {
                    fullscreen.insert(displayID)
                }
            }
        }
        return (current, fullscreen)
    }

    func onScreenFrontToBackIDs(ownerPIDs: Set<pid_t>) -> [(id: CGWindowID, pid: pid_t)] {
        guard !ownerPIDs.isEmpty else { return [] }
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        var result: [(id: CGWindowID, pid: pid_t)] = []
        for info in list {
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.int32Value ?? 0
            guard layer == 0 else { continue }
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            let pid = pid_t((info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0)
            if ownerPIDs.contains(pid) {
                result.append((id, pid))
            }
        }
        return result
    }

    func spaces(forWindowIDs ids: [CGWindowID]) -> [CGWindowID: [UInt64]] {
        var result: [CGWindowID: [UInt64]] = [:]
        guard let proc = copySpacesForWindows else { return result }
        for id in ids {
            var number = Int32(id)
            guard let cfNumber = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &number) else { continue }
            let array = [cfNumber] as CFArray
            guard let spaces = proc(connection, Self.allSpacesSelector, array)?.takeRetainedValue() as? [NSNumber] else {
                continue
            }
            result[id] = spaces.map(\.uint64Value)
        }
        return result
    }

    private struct DisplaySpaces {
        var displayID: CGDirectDisplayID
        var currentSpace: UInt64
        var currentType: Int32
        var spaceTypes: [UInt64: Int32]
    }

    private func managedSpaces() -> [DisplaySpaces]? {
        guard let proc = copyManagedDisplaySpaces,
              let raw = proc(connection)?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        var displays: [DisplaySpaces] = []
        for entry in raw {
            let uuid = (entry["Display Identifier"] as? String) ?? ""
            let displayID = displayID(fromUUID: uuid)
            let current = entry["Current Space"] as? [String: Any]
            let currentID = spaceID(from: current?["ManagedSpaceID"] ?? current?["id64"])
            let currentType = (current?["type"] as? NSNumber)?.int32Value ?? 0
            var types: [UInt64: Int32] = [:]
            if let spaces = entry["Spaces"] as? [[String: Any]] {
                for space in spaces {
                    let id = spaceID(from: space["ManagedSpaceID"] ?? space["id64"])
                    let type = (space["type"] as? NSNumber)?.int32Value ?? 0
                    types[id] = type
                }
            }
            displays.append(DisplaySpaces(
                displayID: displayID,
                currentSpace: currentID,
                currentType: currentType,
                spaceTypes: types
            ))
        }
        return displays
    }

    private func spaceID(from value: Any?) -> UInt64 {
        if let number = value as? NSNumber { return number.uint64Value }
        if let int = value as? UInt64 { return int }
        return 0
    }

    private func displayUUIDString(_ displayID: CGDirectDisplayID) -> String? {
        guard let uuid = DisplayUUID.uuid(for: displayID) else { return nil }
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
    }

    private func displayID(fromUUID uuid: String) -> CGDirectDisplayID {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        for display in displays where displayUUIDString(display)?.caseInsensitiveCompare(uuid) == .orderedSame {
            return display
        }
        return 0
    }
}

private nonisolated enum DisplayUUID {
    private typealias Proc = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFUUID>?
    private static let proc: Proc? = {
        let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
        guard let handle, let symbol = dlsym(handle, "CGDisplayCreateUUIDFromDisplayID") else { return nil }
        return unsafeBitCast(symbol, to: Proc.self)
    }()

    static func uuid(for displayID: CGDirectDisplayID) -> CFUUID? {
        proc?(displayID)?.takeRetainedValue()
    }
}
