import ApplicationServices
import CoreGraphics
import Foundation

nonisolated struct ScanRequest: Sendable {
    struct App: Sendable {
        let pid: pid_t
        let bundleID: String?
        let appName: String
        let isHidden: Bool
    }

    struct Screen: Sendable {
        let displayID: CGDirectDisplayID
        let cocoaFrame: CGRect
    }

    let apps: [App]
    let frontAppPID: pid_t?
    let screens: [Screen]
    let cocoaPrimaryHeight: CGFloat
    let blacklist: Set<String>
    let ignoredBundleIDs: Set<String>
}

nonisolated struct ScanResult: Sendable {
    var windows: [WindowInfo]
    var currentSpaces: [CGDirectDisplayID: UInt64]
    var fullscreenDisplays: Set<CGDirectDisplayID>
    var elements: [CGWindowID: AXElementRef]

    static let empty = ScanResult(
        windows: [],
        currentSpaces: [:],
        fullscreenDisplays: [],
        elements: [:]
    )
}

nonisolated enum ScanGeometry {
    static func looksLikeFullscreen(_ cgFrame: CGRect, screenSizes: [CGSize]) -> Bool {
        screenSizes.contains { size in
            abs(cgFrame.width - size.width) < 4 && abs(cgFrame.height - size.height) < 4
        }
    }

    /// Accessibility does not list these windows. A named window is kept even when
    /// the window server reports an empty frame.
    static func canListOffScreenWindow(layer: Int32, alpha: CGFloat, frame: CGRect, title: String) -> Bool {
        guard layer == 0, alpha > 0 else { return false }
        let sized = frame.width >= 40 && frame.height >= 40
        let named = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return sized || named
    }

    /// True when the window belongs only to Spaces that are not visible on any display.
    static func isAssignedOnlyToOtherSpaces(spaces: [UInt64], visibleSpaces: Set<UInt64>) -> Bool {
        guard !spaces.isEmpty, !visibleSpaces.isEmpty else { return false }
        return spaces.allSatisfy { !visibleSpaces.contains($0) }
    }
}

nonisolated struct ScanCoalescer: Equatable {
    private(set) var isScanning = false
    private(set) var needsRescan = false

    mutating func requestStart() -> Bool {
        if isScanning {
            needsRescan = true
            return false
        }
        isScanning = true
        needsRescan = false
        return true
    }

    mutating func finish() -> Bool {
        isScanning = false
        if needsRescan {
            needsRescan = false
            return true
        }
        return false
    }
}

actor WindowScanner {
    static let shared = WindowScanner()

    private struct ElementIdentity: Hashable {
        let element: AXUIElement

        static func == (lhs: ElementIdentity, rhs: ElementIdentity) -> Bool {
            CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(CFHash(element))
        }
    }

    private struct CachedWindow {
        var windowID: CGWindowID
        var role: String
        var subrole: String
    }

    private var cacheByElement: [ElementIdentity: CachedWindow] = [:]
    private var elementByWindowID: [CGWindowID: AXUIElement] = [:]
    private let spaces: any SpacesProviding

    init(spaces: any SpacesProviding = CGSBridge.shared) {
        self.spaces = spaces
        AXBridge.configureSystemTimeout()
    }

    func element(for windowID: CGWindowID) -> AXElementRef? {
        elementByWindowID[windowID].map(AXElementRef.init)
    }

    func scan(_ request: ScanRequest) -> ScanResult {
        let allCGWindows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []

        var cgByID: [CGWindowID: [String: Any]] = [:]
        cgByID.reserveCapacity(allCGWindows.count)
        var onScreenIDs = Set<CGWindowID>()
        var layer0PIDs = Set<pid_t>()
        for info in allCGWindows {
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            cgByID[id] = info
            if (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true {
                onScreenIDs.insert(id)
            }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.int32Value ?? 0
            if layer == 0, let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value {
                layer0PIDs.insert(pid_t(pid))
            }
        }
        let screenSizes = request.screens.map(\.cocoaFrame.size)

        var windows: [WindowInfo] = []
        var seen = Set<CGWindowID>()
        var liveElements: [CGWindowID: AXUIElement] = [:]

        for app in request.apps {
            if let bundleID = app.bundleID,
               request.ignoredBundleIDs.contains(bundleID) || request.blacklist.contains(bundleID) {
                continue
            }
            guard layer0PIDs.contains(app.pid) else { continue }

            let axWindows = AXBridge.windows(forApp: app.pid)
            var focusedID: CGWindowID?
            if app.pid == request.frontAppPID {
                if let focused = AXBridge.focusedWindow(forApp: app.pid) {
                    focusedID = cachedWindow(for: focused)?.windowID
                }
            }

            for axWindow in axWindows {
                guard let cached = cachedWindow(for: axWindow) else { continue }
                let role = cached.role
                guard role == (kAXWindowRole as String) || role.isEmpty else { continue }
                let subrole = cached.subrole
                var title: String?
                if subrole == "AXFloatingWindow" || subrole == "AXSystemFloatingWindow" {
                    let value = AXBridge.title(of: axWindow)
                    if value.isEmpty { continue }
                    title = value
                }

                let wid = cached.windowID
                if seen.contains(wid) { continue }
                seen.insert(wid)

                let cgInfo = cgByID[wid]
                let layer = (cgInfo?[kCGWindowLayer as String] as? NSNumber)?.int32Value ?? 0
                if layer != 0 { continue }

                let boundsDict = cgInfo?[kCGWindowBounds as String] as? [String: CGFloat]
                let cgFrame: CGRect
                if let boundsDict {
                    cgFrame = CGRect(
                        x: boundsDict["X"] ?? 0,
                        y: boundsDict["Y"] ?? 0,
                        width: boundsDict["Width"] ?? 0,
                        height: boundsDict["Height"] ?? 0
                    )
                } else {
                    cgFrame = AXBridge.frame(of: axWindow) ?? .zero
                }
                if cgFrame.width < 40 || cgFrame.height < 40 { continue }

                let isOnScreen = onScreenIDs.contains(wid)
                let isMinimized = isOnScreen ? false : AXBridge.isMinimized(axWindow)
                let isFullscreen = ScanGeometry.looksLikeFullscreen(cgFrame, screenSizes: screenSizes)
                    ? AXBridge.isFullscreen(axWindow)
                    : false
                if title == nil {
                    let cgTitle = (cgInfo?[kCGWindowName as String] as? String) ?? ""
                    title = cgTitle.isEmpty ? AXBridge.title(of: axWindow) : cgTitle
                }

                liveElements[wid] = axWindow
                windows.append(WindowInfo(
                    id: wid,
                    pid: app.pid,
                    bundleID: app.bundleID,
                    appName: app.appName,
                    title: title ?? "",
                    frame: cgFrame,
                    screenID: ScreenGeometry.displayID(
                        containingCGRect: cgFrame,
                        screens: request.screens.map { ($0.displayID, $0.cocoaFrame) },
                        cocoaPrimaryHeight: request.cocoaPrimaryHeight
                    ),
                    spaces: [],
                    isMinimized: isMinimized,
                    isHidden: app.isHidden,
                    isFullscreen: isFullscreen,
                    isOnScreen: isOnScreen,
                    isTabbed: false,
                    isActive: (app.pid == request.frontAppPID) && (focusedID == wid),
                    layer: layer
                ))
            }
        }

        let foreign = offScreenCandidates(
            cgByID: cgByID,
            seen: seen,
            onScreenIDs: onScreenIDs,
            request: request
        )
        let spaceMap = spaces.spaces(forWindowIDs: windows.map(\.id) + foreign.map(\.id))
        windows = windows.map { window in
            WindowInfo(
                id: window.id,
                pid: window.pid,
                bundleID: window.bundleID,
                appName: window.appName,
                title: window.title,
                frame: window.frame,
                screenID: window.screenID,
                spaces: spaceMap[window.id] ?? [],
                isMinimized: window.isMinimized,
                isHidden: window.isHidden,
                isFullscreen: window.isFullscreen,
                isOnScreen: window.isOnScreen,
                isTabbed: window.isTabbed,
                isActive: window.isActive,
                layer: window.layer
            )
        }

        let displayIDs = request.screens.map(\.displayID)
        let spaceState = spaces.displaySpaceState(displayIDs: displayIDs)
        let visibleSpaces = Set(spaceState.current.values)
        let screenPairs = request.screens.map { (id: $0.displayID, frame: $0.cocoaFrame) }
        for candidate in foreign {
            let windowSpaces = spaceMap[candidate.id] ?? []
            guard ScanGeometry.isAssignedOnlyToOtherSpaces(
                spaces: windowSpaces,
                visibleSpaces: visibleSpaces
            ) else { continue }
            let fullscreen = ScanGeometry.looksLikeFullscreen(candidate.frame, screenSizes: screenSizes)
                && windowSpaces.contains { spaces.isFullscreenSpace($0) }
            windows.append(WindowInfo(
                id: candidate.id,
                pid: candidate.app.pid,
                bundleID: candidate.app.bundleID,
                appName: candidate.app.appName,
                title: candidate.title,
                frame: candidate.frame,
                screenID: ScreenGeometry.displayID(
                    containingCGRect: candidate.frame,
                    screens: screenPairs,
                    cocoaPrimaryHeight: request.cocoaPrimaryHeight
                ),
                spaces: windowSpaces,
                isMinimized: false,
                isHidden: candidate.app.isHidden,
                isFullscreen: fullscreen,
                isOnScreen: false,
                isTabbed: false,
                isActive: false,
                layer: candidate.layer
            ))
        }

        let listed = Set(windows.map(\.id))
        evict(keeping: listed)
        for (id, element) in liveElements {
            elementByWindowID[id] = element
        }

        var elements: [CGWindowID: AXElementRef] = [:]
        elements.reserveCapacity(elementByWindowID.count)
        for (id, element) in elementByWindowID {
            elements[id] = AXElementRef(element)
        }

        return ScanResult(
            windows: windows,
            currentSpaces: spaceState.current,
            fullscreenDisplays: spaceState.fullscreen,
            elements: elements
        )
    }

    func readDockBadges(dockPID: pid_t, nameMap: [String: String]) -> [String: String] {
        let app = AXBridge.application(pid: dockPID)
        let lists = AXBridge.copyElements(app, attribute: kAXChildrenAttribute as String)
        var result: [String: String] = [:]
        for list in lists {
            let items = AXBridge.copyElements(list, attribute: kAXChildrenAttribute as String)
            for item in items {
                guard let label = AXBridge.copyString(item, attribute: "AXStatusLabel"),
                      !label.isEmpty,
                      DockBadgeReader.isBadgeLabel(label) else {
                    continue
                }
                if let bundleID = bundleID(forDockItem: item, nameMap: nameMap) {
                    result[bundleID] = label
                }
            }
        }
        return result
    }

    private struct OffScreenCandidate {
        var id: CGWindowID
        var app: ScanRequest.App
        var title: String
        var frame: CGRect
        var layer: Int32
    }

    /// Layer-0 windows Accessibility did not return. Inactive Spaces are identified
    /// later, once SkyLight has mapped each window id.
    private func offScreenCandidates(
        cgByID: [CGWindowID: [String: Any]],
        seen: Set<CGWindowID>,
        onScreenIDs: Set<CGWindowID>,
        request: ScanRequest
    ) -> [OffScreenCandidate] {
        var eligible: [pid_t: ScanRequest.App] = [:]
        for app in request.apps {
            if let bundleID = app.bundleID,
               request.ignoredBundleIDs.contains(bundleID) || request.blacklist.contains(bundleID) {
                continue
            }
            eligible[app.pid] = app
        }
        var foreign: [OffScreenCandidate] = []
        for (id, info) in cgByID {
            if seen.contains(id) || onScreenIDs.contains(id) { continue }
            let pid = pid_t((info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0)
            guard let app = eligible[pid] else { continue }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.int32Value ?? 0
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            let title = info[kCGWindowName as String] as? String ?? ""
            let frame = Self.cgBounds(info)
            guard ScanGeometry.canListOffScreenWindow(layer: layer, alpha: alpha, frame: frame, title: title) else {
                continue
            }
            foreign.append(OffScreenCandidate(id: id, app: app, title: title, frame: frame, layer: layer))
        }
        foreign.sort { $0.id < $1.id }
        return foreign
    }

    private static func cgBounds(_ info: [String: Any]) -> CGRect {
        guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return .zero }
        return CGRect(
            x: bounds["X"] ?? 0,
            y: bounds["Y"] ?? 0,
            width: bounds["Width"] ?? 0,
            height: bounds["Height"] ?? 0
        )
    }

    private func cachedWindow(for element: AXUIElement) -> CachedWindow? {
        let key = ElementIdentity(element: element)
        if let cached = cacheByElement[key] {
            return cached
        }
        guard let windowID = AXBridge.cgWindowID(for: element) else { return nil }
        let cached = CachedWindow(
            windowID: windowID,
            role: AXBridge.role(of: element),
            subrole: AXBridge.subrole(of: element)
        )
        cacheByElement[key] = cached
        return cached
    }

    private func evict(keeping windowIDs: Set<CGWindowID>) {
        cacheByElement = cacheByElement.filter { windowIDs.contains($0.value.windowID) }
        elementByWindowID = elementByWindowID.filter { windowIDs.contains($0.key) }
    }

    private func bundleID(forDockItem element: AXUIElement, nameMap: [String: String]) -> String? {
        if let url = AXBridge.copyURL(element, attribute: kAXURLAttribute as String)
            ?? AXBridge.copyURL(element, attribute: "AXURL") {
            if let id = Bundle(url: url)?.bundleIdentifier {
                return id
            }
        }
        let title = AXBridge.title(of: element)
        return nameMap[title.lowercased()]
    }
}
