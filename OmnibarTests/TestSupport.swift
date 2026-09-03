import CoreGraphics
import Foundation
import XCTest
@testable import Omnibar

final class IsolatedDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "omnibar.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
func isolatedSettingsStore(_ defaults: UserDefaults) -> SettingsStore {
    SettingsStore(
        defaults: defaults,
        syncLoginItem: { _ in },
        applyDockFromSettings: {},
        revertDock: {}
    )
}

@MainActor
func stubWindow(
    id: CGWindowID,
    bundle: String? = "com.example.app",
    title: String = "Title",
    pid: pid_t = 42,
    screen: CGDirectDisplayID? = 1,
    spaces: [UInt64] = [10],
    minimized: Bool = false,
    hidden: Bool = false,
    fullscreen: Bool = false,
    onScreen: Bool = true,
    tabbed: Bool = false,
    active: Bool = false,
    layer: Int32 = 0,
    appName: String? = nil,
    frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)
) -> WindowInfo {
    WindowInfo(
        id: id,
        pid: pid,
        bundleID: bundle,
        appName: appName ?? bundle ?? "App",
        title: title,
        frame: frame,
        screenID: screen,
        spaces: spaces,
        isMinimized: minimized,
        isHidden: hidden,
        isFullscreen: fullscreen,
        isOnScreen: onScreen,
        isTabbed: tabbed,
        isActive: active,
        layer: layer
    )
}

@MainActor
@discardableResult
func makeStubApp(named name: String, bundleID: String, in directory: URL) throws -> URL {
    let app = directory.appendingPathComponent("\(name).app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": bundleID,
        "CFBundleName": name,
        "CFBundlePackageType": "APPL",
        "CFBundleExecutable": name
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return app
}

func catalogStub(bundleID: String, name: String) -> AppCatalog.CatalogApp {
    AppCatalog.CatalogApp(
        bundleID: bundleID,
        name: name,
        url: URL(fileURLWithPath: "/tmp/\(name).app")
    )
}
