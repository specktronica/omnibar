import AppKit
import Foundation
import Security

/// Detects another Omnibar.app whose code-signing requirement differs from this
/// process. System Settings binds Accessibility and Screen Recording grants to
/// the copy Launch Services resolves for the bundle ID, not necessarily the
/// running binary.
enum InstallConflict {
    static func designatedRequirement(at url: URL) -> String? {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        let requirementStatus = SecCodeCopyDesignatedRequirement(staticCode, [], &requirement)
        guard requirementStatus == errSecSuccess, let requirement else { return nil }
        var requirementString: CFString?
        let stringStatus = SecRequirementCopyString(requirement, [], &requirementString)
        guard stringStatus == errSecSuccess, let requirementString else { return nil }
        return requirementString as String
    }

    /// Returns `preferredURL` when it is a different copy with a different
    /// designated requirement. Same-path URLs and same-requirement copies
    /// (two Developer ID builds, App Translocation) are not a conflict.
    static func resolve(
        ourURL: URL,
        preferredURL: URL?,
        ourRequirement: String?,
        theirRequirement: String?
    ) -> URL? {
        guard let preferredURL else { return nil }
        let ours = canonicalPath(ourURL)
        let theirs = canonicalPath(preferredURL)
        guard ours != theirs else { return nil }
        guard let ourRequirement, let theirRequirement else { return nil }
        guard ourRequirement != theirRequirement else { return nil }
        return preferredURL
    }

    private static func canonicalPath(_ url: URL) -> String {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        if path.count > 1, path.hasSuffix("/") {
            return String(path.dropLast())
        }
        return path
    }

    static func detect() -> URL? {
        let ourURL = Bundle.main.bundleURL
        let preferredURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "io.specktronica.omnibar"
        )
        return resolve(
            ourURL: ourURL,
            preferredURL: preferredURL,
            ourRequirement: designatedRequirement(at: ourURL),
            theirRequirement: preferredURL.flatMap { designatedRequirement(at: $0) }
        )
    }
}
