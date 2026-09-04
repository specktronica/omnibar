import AppKit
import Foundation

enum SupportLinks: Sendable {
    static let koFiURLString = "https://ko-fi.com/specktronica"
    static let koFi = URL(string: koFiURLString)!
    static let bitcoin = "bc1qzd7yvqyyxnz0yd5rrkr3sfathr4ne4zff2a0w8"
    static let ethereum = "0xA949241b60e2E7fC0b82b9cd7fB74b2aF78592F7"

    static func openKoFi() {
        NSWorkspace.shared.open(koFi)
    }

    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
