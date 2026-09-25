import CoreGraphics
import Foundation

/// Control+Option chord used to open and close the Start Menu.
///
/// Pressing the chord emits `.pressed`. Releasing it with no other key, click,
/// or scroll emits `.tapped`. Another modifier, or `otherInput`, cancels the
/// tap so the same keys can still be held for tiling shortcuts.
nonisolated enum StartMenuShortcut: Sendable {
    struct Modifiers: OptionSet, Equatable, Sendable {
        var rawValue: UInt8

        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        static let chord: Modifiers = [.control, .option]
    }

    enum Phase: Equatable, Sendable {
        case idle
        case armed
        case suppressed
    }

    struct State: Equatable, Sendable {
        var phase: Phase = .idle
        var modifiers: Modifiers = []
    }

    enum Input: Equatable, Sendable {
        case modifiers(Modifiers)
        case otherInput
    }

    enum Effect: Equatable, Sendable {
        case none
        case pressed
        case tapped
    }

    static func reduce(_ state: inout State, _ input: Input) -> Effect {
        switch input {
        case .otherInput:
            if state.phase == .armed {
                state.phase = .suppressed
            }
            return .none
        case .modifiers(let next):
            let previous = state.modifiers
            guard next != previous else { return .none }
            state.modifiers = next
            switch state.phase {
            case .suppressed:
                if !next.contains(.chord) {
                    state.phase = .idle
                }
                return .none
            case .armed:
                if previous == .chord, !next.contains(.chord) {
                    state.phase = .idle
                    return .tapped
                }
                if previous == .chord, next != .chord {
                    state.phase = .suppressed
                }
                return .none
            case .idle:
                if next == .chord, previous.isSubset(of: .chord) {
                    state.phase = .armed
                    return .pressed
                }
                return .none
            }
        }
    }
}

/// Which display should show the Start Menu for a shortcut tap.
nonisolated enum StartMenuShortcutTarget: Sendable {
    static func presentationDisplayID(
        cursorDisplayID: CGDirectDisplayID?,
        visibleDisplayIDs: [CGDirectDisplayID],
        preferredDisplayID: CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        if let cursorDisplayID, visibleDisplayIDs.contains(cursorDisplayID) {
            return cursorDisplayID
        }
        if let preferredDisplayID, visibleDisplayIDs.contains(preferredDisplayID) {
            return preferredDisplayID
        }
        return visibleDisplayIDs.first
    }
}
