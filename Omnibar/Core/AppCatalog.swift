import AppKit
import Foundation

final class AppCatalog {
    static let shared = AppCatalog()

    struct CatalogApp: Identifiable, Hashable {
        var id: String { bundleID + url.path }
        let bundleID: String
        let name: String
        let url: URL
    }

    private(set) var apps: [CatalogApp] = []
    private(set) var recents: [CatalogApp] = []
    private var sources: [DispatchSourceFileSystemObject] = []
    private let recentsKey = "omnibar.recents.v1"
    private var workspaceTokens: [NSObjectProtocol] = []

    func start() {
        refresh()
        watch()
        let saved = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        recents = saved.compactMap { bundleID in
            apps.first { $0.bundleID == bundleID } ?? catalogApp(bundleID: bundleID)
        }
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in
                if let bundleID {
                    self?.recordLaunch(bundleID: bundleID)
                }
            }
        }
        workspaceTokens.append(token)
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens.removeAll()
    }

    static let defaultDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    ]

    func refresh() {
        apps = collectApps(from: Self.defaultDirectories)
        NotificationCenter.default.post(name: .omnibarCatalogDidChange, object: nil)
    }

    func collectApps(from directories: [URL]) -> [CatalogApp] {
        var found: [CatalogApp] = []
        var seen = Set<String>()
        for directory in directories {
            found.append(contentsOf: scan(directory: directory, seen: &seen))
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func recordLaunch(bundleID: String) {
        guard bundleID != "io.specktronica.omnibar" else { return }
        recents.removeAll { $0.bundleID == bundleID }
        if let app = apps.first(where: { $0.bundleID == bundleID }) ?? catalogApp(bundleID: bundleID) {
            recents.insert(app, at: 0)
        }
        let limit = max(1, SettingsStore.shared.settings.recentAppsLimit)
        if recents.count > limit {
            recents = Array(recents.prefix(limit))
        }
        UserDefaults.standard.set(recents.map(\.bundleID), forKey: recentsKey)
        NotificationCenter.default.post(name: .omnibarCatalogDidChange, object: nil)
    }

    func search(_ query: String) -> [CatalogApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    func groupedByLetter(_ list: [CatalogApp]) -> [(letter: String, apps: [CatalogApp])] {
        let grouped = Dictionary(grouping: list) { app -> String in
            let first = app.name.first.map { String($0).uppercased() } ?? "#"
            if first.range(of: "[A-Z]", options: .regularExpression) != nil {
                return first
            }
            return "#"
        }
        return grouped.keys.sorted().map { letter in
            (letter, grouped[letter]!.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    func launch(_ app: CatalogApp) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        recordLaunch(bundleID: app.bundleID)
    }

    func launch(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        recordLaunch(bundleID: bundleID)
    }

    private func catalogApp(bundleID: String) -> CatalogApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return CatalogApp(bundleID: bundleID, name: IconCache.appName(for: bundleID), url: url)
    }

    private func scan(directory: URL, seen: inout Set<String>) -> [CatalogApp] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [CatalogApp] = []
        for url in contents {
            if isAppBundle(url) {
                if let app = catalogApp(from: url), seen.insert(app.bundleID).inserted {
                    result.append(app)
                }
            } else if isDirectory(url) {
                let nested = (try? fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isPackageKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for child in nested where isAppBundle(child) {
                    if let app = catalogApp(from: child), seen.insert(app.bundleID).inserted {
                        result.append(app)
                    }
                }
            }
        }
        return result
    }

    private func isAppBundle(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "app"
    }

    private func isDirectory(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) {
            return values.isDirectory == true && values.isPackage != true
        }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue && !isAppBundle(url)
    }

    func catalogApp(from url: URL) -> CatalogApp? {
        let resolved = url.resolvingSymlinksInPath()
        guard isAppBundle(resolved) else { return nil }
        let info = infoDictionary(forAppAt: resolved)
        let bundle = Bundle(url: resolved)
        let bundleID = bundle?.bundleIdentifier
            ?? (info?["CFBundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "app.\(resolved.path)"
        let name = appName(from: info, bundle: bundle, url: resolved)
        return CatalogApp(bundleID: bundleID, name: name, url: resolved)
    }

    private func infoDictionary(forAppAt url: URL) -> [String: Any]? {
        let candidates = [
            url.appendingPathComponent("Contents/Info.plist"),
            url.appendingPathComponent("Wrapper/Info.plist")
        ]
        for plist in candidates {
            if let info = NSDictionary(contentsOf: plist) as? [String: Any] {
                return info
            }
        }
        return Bundle(url: url)?.infoDictionary
    }

    private func appName(from info: [String: Any]?, bundle: Bundle?, url: URL) -> String {
        if let bundle {
            if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !display.isEmpty {
                return display
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
                return name
            }
        }
        if let display = info?["CFBundleDisplayName"] as? String, !display.isEmpty {
            return display
        }
        if let name = info?["CFBundleName"] as? String, !name.isEmpty {
            return name
        }
        let displayName = FileManager.default.displayName(atPath: url.path)
        if displayName.hasSuffix(".app") {
            return url.deletingPathExtension().lastPathComponent
        }
        return displayName.isEmpty ? url.deletingPathExtension().lastPathComponent : displayName
    }

    private func watch() {
        let paths = [
            "/Applications",
            "/System/Applications",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]
        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.refresh()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            sources.append(source)
        }
    }
}
