import XCTest
@testable import Omnibar

@MainActor
final class InstallConflictTests: XCTestCase {
    private let local = URL(fileURLWithPath: "/Users/me/build/Omnibar.app")
    private let cask = URL(fileURLWithPath: "/Applications/Omnibar.app")

    func testResolveReturnsNilWhenPathsMatch() {
        XCTAssertNil(
            InstallConflict.resolve(
                ourURL: local,
                preferredURL: local,
                ourRequirement: "dev",
                theirRequirement: "id"
            )
        )
        let trailingSlash = URL(fileURLWithPath: "/Users/me/build/Omnibar.app/")
        XCTAssertNil(
            InstallConflict.resolve(
                ourURL: local,
                preferredURL: trailingSlash,
                ourRequirement: "dev",
                theirRequirement: "id"
            )
        )
    }

    func testResolveReturnsNilWhenRequirementsMatch() {
        XCTAssertNil(
            InstallConflict.resolve(
                ourURL: local,
                preferredURL: cask,
                ourRequirement: "same",
                theirRequirement: "same"
            )
        )
    }

    func testResolveReturnsPreferredURLWhenRequirementDiffers() {
        XCTAssertEqual(
            InstallConflict.resolve(
                ourURL: local,
                preferredURL: cask,
                ourRequirement: "dev",
                theirRequirement: "id"
            ),
            cask
        )
    }

    func testResolveReturnsNilWhenPreferredURLIsMissing() {
        XCTAssertNil(
            InstallConflict.resolve(
                ourURL: local,
                preferredURL: nil,
                ourRequirement: "dev",
                theirRequirement: nil
            )
        )
    }

    func testDesignatedRequirementForFinderContainsIdentifier() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let requirement = InstallConflict.designatedRequirement(at: url)
        XCTAssertNotNil(requirement)
        XCTAssertTrue(
            requirement?.contains("com.apple.finder") == true,
            "expected Finder identifier in \(requirement ?? "nil")"
        )
    }
}
