import XCTest
@testable import Omnibar

@MainActor
final class StartLogoGeometryTests: XCTestCase {
    func testHexRoundTrip() {
        let color = RGBAColor(hex: 0xAABBCC, alpha: 0.5)
        XCTAssertEqual(color.hexRGB, 0xAABBCC)
        XCTAssertEqual(color.alpha, 0.5, accuracy: 0.0001)
        XCTAssertEqual(color.red, 170.0 / 255.0, accuracy: 0.0001)
    }

    func testMissingAlphaDefaultsToOne() throws {
        let data = Data(#"{"red":1,"green":0,"blue":0}"#.utf8)
        let color = try JSONDecoder().decode(RGBAColor.self, from: data)
        XCTAssertEqual(color.alpha, 1)
        XCTAssertEqual(color.red, 1)
    }

    func testMatchesQuantizesComponents() {
        let a = RGBAColor(red: 1, green: 0, blue: 0)
        let b = RGBAColor(red: 1 - 1.0 / 512.0, green: 0, blue: 0)
        XCTAssertTrue(a.matches(b))
        XCTAssertNotEqual(a, b)
        XCTAssertFalse(a.matches(RGBAColor(red: 0, green: 0, blue: 0)))
    }

    func testPackingInnerRadius() {
        let packing = StartLogoPacking(rect: NSRect(x: 0, y: 0, width: 200, height: 200), insetFactor: 0)
        let outer: CGFloat = (200 - 2) / 2
        XCTAssertEqual(packing.outerR, outer, accuracy: 0.0001)
        XCTAssertEqual(packing.innerR, outer / (1 + CGFloat(2).squareRoot()), accuracy: 0.0001)
        XCTAssertEqual(packing.offset, packing.innerR * CGFloat(2).squareRoot(), accuracy: 0.0001)
    }
}
