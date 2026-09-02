import Foundation

enum StartButtonAction: String, Codable, CaseIterable, Identifiable {
    case startMenu
    case launchpad
    case spotlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startMenu: "Start Menu"
        case .launchpad: "Launchpad"
        case .spotlight: "Spotlight"
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var followSystemAppearance: Bool = true
    var forceDarkMode: Bool = false
    var transparency: Double = 0.55
    var taskbarHeight: Double = 40
    var fontSize: Double = 12
    var iconOnly: Bool = false
    var groupByApplication: Bool = true
    var showTabsAsItems: Bool = true
    var indicateMinimizedHidden: Bool = true
    var hideOnClickInsteadOfMinimize: Bool = false
    var thumbnailDelay: Double = 0.4
    var thumbnailSize: Double = 240
    var showTitleInThumbnail: Bool = false
    var showWindowsFromAllScreens: Bool = false
    var mainDisplayOnly: Bool = false
    var hiddenDisplayIDs: [UInt32] = []
    var autoResizeOverlapping: Bool = true
    var overlapSkipBundleIDs: [String] = []
    var keepOrderAcrossSpaceChange: Bool = true
    var allowDragReorder: Bool = true
    var autoHide: Bool = false
    var pollInterval: Double = 1.5
    var fullyHideDock: Bool = true
    var launchAtLogin: Bool = false
    var startButtonAction: StartButtonAction = .startMenu
    var recentAppsLimit: Int = 10

    static let `default` = AppSettings()

    var appearanceIsDarkForced: Bool { !followSystemAppearance && forceDarkMode }

    func isDisplayHidden(_ displayID: UInt32) -> Bool {
        hiddenDisplayIDs.contains(displayID)
    }
}
