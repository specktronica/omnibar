import Carbon
import Foundation

/// Global Left/Right Arrow hotkeys for keyboard tiling. Uses Carbon
/// `RegisterEventHotKey`, which needs no Input Monitoring grant and does not
/// see any other keystrokes.
final class TilingHotkeys {
    static let shared = TilingHotkeys()

    private enum HotKey: UInt32 {
        case left = 1
        case right = 2

        var virtualKey: UInt32 {
            switch self {
            case .left: UInt32(kVK_LeftArrow)
            case .right: UInt32(kVK_RightArrow)
            }
        }

        var direction: TileDirection {
            switch self {
            case .left: .left
            case .right: .right
            }
        }
    }

    private static let signature: OSType = "OMTL".utf8.reduce(0) { ($0 << 8) | OSType($1) }

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var registeredModifiers: TilingModifiers?
    private var settingsObserver: NSObjectProtocol?

    func start() {
        if settingsObserver == nil {
            settingsObserver = NotificationCenter.default.addObserver(
                forName: .omnibarSettingsDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.applySettings()
                }
            }
        }
        applySettings()
    }

    func stop() {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        unregister()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    private func applySettings() {
        let settings = SettingsStore.shared.settings
        guard settings.tilingShortcutsEnabled else {
            unregister()
            return
        }
        if registeredModifiers == settings.tilingModifiers, !hotKeyRefs.isEmpty {
            return
        }
        unregister()
        register(modifiers: settings.tilingModifiers)
    }

    private func register(modifiers: TilingModifiers) {
        installHandlerIfNeeded()
        for key in [HotKey.left, HotKey.right] {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: key.rawValue)
            let status = RegisterEventHotKey(
                key.virtualKey,
                modifiers.carbonFlags,
                id,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
            } else if status == OSStatus(eventHotKeyExistsErr) {
                NSLog("Omnibar tiling hotkey \(modifiers.symbol)\(key == .left ? "←" : "→") is owned by another app")
            } else {
                NSLog("Omnibar tiling hotkey registration failed: \(status)")
            }
        }
        registeredModifiers = modifiers
    }

    private func unregister() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        registeredModifiers = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            tilingHotKeyHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }

    fileprivate func handle(hotKeyID: UInt32) {
        guard let key = HotKey(rawValue: hotKeyID) else { return }
        WindowTiler.shared.tileFocusedWindow(key.direction)
    }
}

/// Carbon calls this on the main thread, but the C signature cannot carry
/// actor isolation, so the work hops to the main actor explicitly.
private nonisolated func tilingHotKeyHandler(
    _ handler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    Task { @MainActor in
        TilingHotkeys.shared.handle(hotKeyID: id)
    }
    return noErr
}
