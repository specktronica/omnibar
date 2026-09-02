import ApplicationServices
import CoreGraphics
import Foundation

nonisolated struct AXElementRef: @unchecked Sendable {
    nonisolated(unsafe) let element: AXUIElement

    nonisolated init(_ element: AXUIElement) {
        self.element = element
    }
}

nonisolated enum AXBridge {
    static let systemTimeout: Float = 1.0
    static let appTimeout: Float = 0.5

    static func configureSystemTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), systemTimeout)
    }

    static func application(pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, appTimeout)
        return app
    }

    static func windows(forApp pid: pid_t) -> [AXUIElement] {
        copyElements(application(pid: pid), attribute: kAXWindowsAttribute as String)
    }

    static func focusedWindow(forApp pid: pid_t) -> AXUIElement? {
        copyElement(application(pid: pid), attribute: kAXFocusedWindowAttribute as String)
    }

    static func title(of element: AXUIElement) -> String {
        copyString(element, attribute: kAXTitleAttribute as String) ?? ""
    }

    static func role(of element: AXUIElement) -> String {
        copyString(element, attribute: kAXRoleAttribute as String) ?? ""
    }

    static func subrole(of element: AXUIElement) -> String {
        copyString(element, attribute: kAXSubroleAttribute as String) ?? ""
    }

    static func isMinimized(_ element: AXUIElement) -> Bool {
        copyBool(element, attribute: kAXMinimizedAttribute as String) ?? false
    }

    static func isFullscreen(_ element: AXUIElement) -> Bool {
        copyBool(element, attribute: "AXFullScreen") ?? false
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = copyPoint(element, attribute: kAXPositionAttribute as String),
              let size = copySize(element, attribute: kAXSizeAttribute as String) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    static func cgWindowID(for element: AXUIElement) -> CGWindowID? {
        WindowIDResolver.windowID(for: element)
    }

    static func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    static func setMinimized(_ element: AXUIElement, _ minimized: Bool) {
        setBool(element, attribute: kAXMinimizedAttribute as String, value: minimized)
    }

    static func setFullscreen(_ element: AXUIElement, _ fullscreen: Bool) {
        setBool(element, attribute: "AXFullScreen", value: fullscreen)
    }

    static func pressCloseButton(_ element: AXUIElement) {
        if let button = copyElement(element, attribute: kAXCloseButtonAttribute as String) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    static func pressMinimizeButton(_ element: AXUIElement) {
        if let button = copyElement(element, attribute: kAXMinimizeButtonAttribute as String) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    static func pressZoomButton(_ element: AXUIElement) {
        if let button = copyElement(element, attribute: kAXZoomButtonAttribute as String) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    static func element(forWindowID windowID: CGWindowID, pid: pid_t) -> AXUIElement? {
        windows(forApp: pid).first { cgWindowID(for: $0) == windowID }
    }

    static func copyString(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success else { return nil }
        if let string = value as? String { return string }
        return nil
    }

    static func copyBool(_ element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success else { return nil }
        return value as? Bool
    }

    static func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success else { return nil }
        return (value as! AXUIElement)
    }

    static func copyElements(_ element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let array = value as? [AXUIElement] else { return [] }
        return array
    }

    static func copyURL(_ element: AXUIElement, attribute: String) -> URL? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success else { return nil }
        if let url = value as? URL { return url }
        if let string = value as? String { return URL(string: string) }
        return nil
    }

    static func setBool(_ element: AXUIElement, attribute: String, value: Bool) {
        let cfValue: CFBoolean = value ? kCFBooleanTrue : kCFBooleanFalse
        AXUIElementSetAttributeValue(element, attribute as CFString, cfValue)
    }

    static func copyPoint(_ element: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let axValue = value else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func copySize(_ element: AXUIElement, attribute: String) -> CGSize? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let axValue = value else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    static func setSize(_ element: AXUIElement, _ size: CGSize) {
        var mutable = size
        if let axValue = AXValueCreate(.cgSize, &mutable) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axValue)
        }
    }

    static func setPosition(_ element: AXUIElement, _ point: CGPoint) {
        var mutable = point
        if let axValue = AXValueCreate(.cgPoint, &mutable) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axValue)
        }
    }

    static func findMenuItem(pid: pid_t, titles: [String]) -> AXUIElement? {
        let app = application(pid: pid)
        guard let menuBar = copyElement(app, attribute: kAXMenuBarAttribute as String) else { return nil }
        let menus = copyElements(menuBar, attribute: kAXChildrenAttribute as String)
        for menuBarItem in menus {
            let menuChildren = copyElements(menuBarItem, attribute: kAXChildrenAttribute as String)
            if let found = findMenuItem(in: menuChildren, titles: titles) {
                return found
            }
        }
        return nil
    }

    private static func findMenuItem(in items: [AXUIElement], titles: [String]) -> AXUIElement? {
        let lowered = Set(titles.map { $0.lowercased() })
        for item in items {
            let title = copyString(item, attribute: kAXTitleAttribute as String)?.lowercased() ?? ""
            if lowered.contains(title) {
                return item
            }
            let children = copyElements(item, attribute: kAXChildrenAttribute as String)
            if let nested = findMenuItem(in: children, titles: titles) {
                return nested
            }
        }
        return nil
    }

    static func press(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
}

private nonisolated enum WindowIDResolver {
    private typealias GetWindowProc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let proc: GetWindowProc? = {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let handle, let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindowProc.self)
    }()

    static func windowID(for element: AXUIElement) -> CGWindowID? {
        guard let proc else { return nil }
        var id: CGWindowID = 0
        let err = proc(element, &id)
        guard err == .success, id != 0 else { return nil }
        return id
    }
}

final class AXObserverBox: @unchecked Sendable {
    nonisolated(unsafe) let observer: AXObserver
    let pid: pid_t

    init?(pid: pid_t, callback: AXObserverCallback) {
        var observer: AXObserver?
        let err = AXObserverCreate(pid, callback, &observer)
        guard err == .success, let observer else { return nil }
        self.observer = observer
        self.pid = pid
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    func add(notification: String, element: AXUIElement) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, notification as CFString, refcon)
    }

    deinit {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
}
