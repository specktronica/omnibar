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
    var startLogo: StartLogoPalette = .classic

    static let `default` = AppSettings()

    var appearanceIsDarkForced: Bool { !followSystemAppearance && forceDarkMode }

    var compactItems: Bool { iconOnly || groupByApplication }

    func isDisplayHidden(_ displayID: UInt32) -> Bool {
        hiddenDisplayIDs.contains(displayID)
    }

    func matchesExceptStartLogo(_ other: AppSettings) -> Bool {
        var lhs = self
        var rhs = other
        lhs.startLogo = .classic
        rhs.startLogo = .classic
        return lhs == rhs
    }
}

extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case followSystemAppearance
        case forceDarkMode
        case transparency
        case taskbarHeight
        case fontSize
        case iconOnly
        case groupByApplication
        case showTabsAsItems
        case indicateMinimizedHidden
        case hideOnClickInsteadOfMinimize
        case thumbnailDelay
        case thumbnailSize
        case showTitleInThumbnail
        case showWindowsFromAllScreens
        case mainDisplayOnly
        case hiddenDisplayIDs
        case autoResizeOverlapping
        case overlapSkipBundleIDs
        case keepOrderAcrossSpaceChange
        case allowDragReorder
        case autoHide
        case pollInterval
        case fullyHideDock
        case launchAtLogin
        case startButtonAction
        case recentAppsLimit
        case startLogo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.default
        followSystemAppearance = try container.decodeIfPresent(Bool.self, forKey: .followSystemAppearance)
            ?? defaults.followSystemAppearance
        forceDarkMode = try container.decodeIfPresent(Bool.self, forKey: .forceDarkMode) ?? defaults.forceDarkMode
        transparency = try container.decodeIfPresent(Double.self, forKey: .transparency) ?? defaults.transparency
        taskbarHeight = try container.decodeIfPresent(Double.self, forKey: .taskbarHeight) ?? defaults.taskbarHeight
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? defaults.fontSize
        iconOnly = try container.decodeIfPresent(Bool.self, forKey: .iconOnly) ?? defaults.iconOnly
        groupByApplication = try container.decodeIfPresent(Bool.self, forKey: .groupByApplication)
            ?? defaults.groupByApplication
        showTabsAsItems = try container.decodeIfPresent(Bool.self, forKey: .showTabsAsItems) ?? defaults.showTabsAsItems
        indicateMinimizedHidden = try container.decodeIfPresent(Bool.self, forKey: .indicateMinimizedHidden)
            ?? defaults.indicateMinimizedHidden
        hideOnClickInsteadOfMinimize = try container.decodeIfPresent(Bool.self, forKey: .hideOnClickInsteadOfMinimize)
            ?? defaults.hideOnClickInsteadOfMinimize
        thumbnailDelay = try container.decodeIfPresent(Double.self, forKey: .thumbnailDelay) ?? defaults.thumbnailDelay
        thumbnailSize = try container.decodeIfPresent(Double.self, forKey: .thumbnailSize) ?? defaults.thumbnailSize
        showTitleInThumbnail = try container.decodeIfPresent(Bool.self, forKey: .showTitleInThumbnail)
            ?? defaults.showTitleInThumbnail
        showWindowsFromAllScreens = try container.decodeIfPresent(Bool.self, forKey: .showWindowsFromAllScreens)
            ?? defaults.showWindowsFromAllScreens
        mainDisplayOnly = try container.decodeIfPresent(Bool.self, forKey: .mainDisplayOnly) ?? defaults.mainDisplayOnly
        hiddenDisplayIDs = try container.decodeIfPresent([UInt32].self, forKey: .hiddenDisplayIDs)
            ?? defaults.hiddenDisplayIDs
        autoResizeOverlapping = try container.decodeIfPresent(Bool.self, forKey: .autoResizeOverlapping)
            ?? defaults.autoResizeOverlapping
        overlapSkipBundleIDs = try container.decodeIfPresent([String].self, forKey: .overlapSkipBundleIDs)
            ?? defaults.overlapSkipBundleIDs
        keepOrderAcrossSpaceChange = try container.decodeIfPresent(Bool.self, forKey: .keepOrderAcrossSpaceChange)
            ?? defaults.keepOrderAcrossSpaceChange
        allowDragReorder = try container.decodeIfPresent(Bool.self, forKey: .allowDragReorder)
            ?? defaults.allowDragReorder
        autoHide = try container.decodeIfPresent(Bool.self, forKey: .autoHide) ?? defaults.autoHide
        pollInterval = try container.decodeIfPresent(Double.self, forKey: .pollInterval) ?? defaults.pollInterval
        fullyHideDock = try container.decodeIfPresent(Bool.self, forKey: .fullyHideDock) ?? defaults.fullyHideDock
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        startButtonAction = try container.decodeIfPresent(StartButtonAction.self, forKey: .startButtonAction)
            ?? defaults.startButtonAction
        recentAppsLimit = try container.decodeIfPresent(Int.self, forKey: .recentAppsLimit) ?? defaults.recentAppsLimit
        startLogo = try container.decodeIfPresent(StartLogoPalette.self, forKey: .startLogo) ?? defaults.startLogo
    }
}
