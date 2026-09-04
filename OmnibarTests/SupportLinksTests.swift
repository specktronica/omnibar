import XCTest
@testable import Omnibar

@MainActor
final class SupportLinksTests: XCTestCase {
    func testKoFiURL() {
        XCTAssertEqual(SupportLinks.koFi.scheme, "https")
        XCTAssertEqual(SupportLinks.koFi.host, "ko-fi.com")
        XCTAssertEqual(SupportLinks.koFi.path, "/specktronica")
        XCTAssertEqual(SupportLinks.koFi.absoluteString, SupportLinks.koFiURLString)
    }

    func testBitcoinAddress() {
        XCTAssertTrue(SupportLinks.bitcoin.hasPrefix("bc1"))
        XCTAssertEqual(SupportLinks.bitcoin, "bc1qzd7yvqyyxnz0yd5rrkr3sfathr4ne4zff2a0w8")
    }

    func testEthereumAddress() {
        XCTAssertTrue(SupportLinks.ethereum.hasPrefix("0x"))
        let hex = String(SupportLinks.ethereum.dropFirst(2))
        XCTAssertEqual(hex.count, 40)
        XCTAssertTrue(hex.allSatisfy(\.isHexDigit))
        XCTAssertEqual(SupportLinks.ethereum, "0xA949241b60e2E7fC0b82b9cd7fB74b2aF78592F7")
    }
}
