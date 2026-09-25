import AppKit
import Foundation

/// Global Control+Option tap that opens the Start Menu, and closes it if it
/// is already open. Listening uses `NSEvent` monitors, which need the
/// Accessibility grant the taskbar already requires. No keystrokes are stored.
final class StartMenuHotkey {
    static let shared = StartMenuHotkey()

    private var state = StartMenuShortcut.State()
    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }
        addMonitor(matching: .flagsChanged, global: false)
        addMonitor(matching: .flagsChanged, global: true)
        let cancel: NSEvent.EventTypeMask = [
            .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel
        ]
        addMonitor(matching: cancel, global: false)
        addMonitor(matching: cancel, global: true)
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        state = StartMenuShortcut.State()
    }

    /// A tiling hotkey consumed the chord, so releasing the modifiers must not open the menu.
    func noteOtherInput() {
        apply(.otherInput)
    }

    private func apply(_ input: StartMenuShortcut.Input) {
        switch StartMenuShortcut.reduce(&state, input) {
        case .none:
            break
        case .pressed:
            guard ScreenMonitor.shared.isAnyStartMenuVisible else { return }
            apply(.otherInput)
            ScreenMonitor.shared.dismissStartMenus()
        case .tapped:
            ScreenMonitor.shared.presentStartMenu()
        }
    }

    private func addMonitor(matching mask: NSEvent.EventTypeMask, global: Bool) {
        if global {
            guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
                let input = startMenuShortcutInput(from: event)
                Task { @MainActor in
                    self?.apply(input)
                }
            }) else { return }
            monitors.append(monitor)
        } else {
            guard let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                let input = startMenuShortcutInput(from: event)
                Task { @MainActor in
                    self?.apply(input)
                }
                return event
            }) else { return }
            monitors.append(monitor)
        }
    }
}

private nonisolated func startMenuShortcutInput(from event: NSEvent) -> StartMenuShortcut.Input {
    guard event.type == .flagsChanged else { return .otherInput }
    return .modifiers(startMenuModifiers(event.modifierFlags))
}

private nonisolated func startMenuModifiers(_ flags: NSEvent.ModifierFlags) -> StartMenuShortcut.Modifiers {
    var modifiers = StartMenuShortcut.Modifiers()
    if flags.contains(.control) { modifiers.insert(.control) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    if flags.contains(.command) { modifiers.insert(.command) }
    return modifiers
}
