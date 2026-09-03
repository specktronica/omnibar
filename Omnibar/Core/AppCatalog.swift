import AppKit
import Foundation

final class AppCatalog {
    static let shared = AppCatalog()

    struct CatalogApp: Identifiable, Hashable, Sendable {
        var id: String { bundleID + url.path }
        let bundleID: String
        let name: String
        let url: URL
    }

    private(set) var apps: [CatalogApp] = []
    private(set) var recents: [CatalogApp] = []
    private(set) var grouped: [(letter: String, apps: [CatalogApp])] = []
    private var sources: [DispatchSourceFileSystemObject] = []
    private let recentsKey = "omnibar.recents.v1"
    private var workspaceTokens: [NSObjectProtocol] = []
    private var scanGeneration = 0
    private var debounceWork: DispatchWorkItem?
    private static let scanQueue = DispatchQueue(label: "io.specktronica.omnibar.catalog", qos: .utility)

    func start() {
        let saved = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        recents = saved.compactMap { bundleID in
            catalogApp(bundleID: bundleID)
        }
        refresh()
        watch()
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
        debounceWork?.cancel()
        debounceWork = nil
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
        scheduleScan(delay: 0)
    }

    func collectApps(from directories: [URL]) -> [CatalogApp] {
        Self.collectApps(from: directories)
    }

    nonisolated static func collectApps(from directories: [URL]) -> [CatalogApp] {
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
        Self.filter(apps, query: query)
    }

    func groups(matching query: String) -> [(letter: String, apps: [CatalogApp])] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return grouped }
        return groupedByLetter(Self.filter(apps, query: trimmed))
    }

    nonisolated func groupedByLetter(_ list: [CatalogApp]) -> [(letter: String, apps: [CatalogApp])] {
        Self.groupedByLetter(list)
    }

    nonisolated static func groupedByLetter(_ list: [CatalogApp]) -> [(letter: String, apps: [CatalogApp])] {
        guard !list.isEmpty else { return [] }
        let sorted = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var result: [(letter: String, apps: [CatalogApp])] = []
        for app in sorted {
            let letter = letter(for: app.name)
            if result.last?.letter == letter {
                result[result.count - 1].apps.append(app)
            } else {
                result.append((letter, [app]))
            }
        }
        return result
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

    nonisolated static func filter(_ list: [CatalogApp], query: String) -> [CatalogApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    nonisolated static func letter(for name: String) -> String {
        guard let first = name.first else { return "#" }
        let upper = String(first).uppercased()
        guard let character = upper.first, character >= "A", character <= "Z" else { return "#" }
        return String(character)
    }

    private func scheduleScan(delay: TimeInterval) {
        debounceWork?.cancel()
        if delay <= 0 {
            beginScan()
            return
        }
        let work = DispatchWorkItem {
            Task { @MainActor in
                AppCatalog.shared.beginScan()
            }
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func beginScan() {
        debounceWork?.cancel()
        debounceWork = nil
        scanGeneration += 1
        let generation = scanGeneration
        let directories = Self.defaultDirectories
        Self.scanQueue.async {
            let found = AppCatalog.collectApps(from: directories)
            Task { @MainActor in
                AppCatalog.shared.finishScan(generation: generation, found: found)
            }
        }
    }

    private func finishScan(generation: Int, found: [CatalogApp]) {
        guard generation == scanGeneration else { return }
        applyScan(found)
    }

    private func applyScan(_ found: [CatalogApp]) {
        apps = found
        grouped = Self.groupedByLetter(found)
        recents = recents.compactMap { recent in
            found.first { $0.bundleID == recent.bundleID } ?? recent
        }
        NotificationCenter.default.post(name: .omnibarCatalogDidChange, object: nil)
        let urls = found.map(\.url)
        Task.detached(priority: .utility) {
            IconCache.prefetch(urls: urls)
        }
    }

    nonisolated private static func scan(directory: URL, seen: inout Set<String>) -> [CatalogApp] {
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

    nonisolated private static func isAppBundle(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "app"
    }

    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) {
            return values.isDirectory == true && values.isPackage != true
        }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue && !isAppBundle(url)
    }

    nonisolated func catalogApp(from url: URL) -> CatalogApp? {
        Self.catalogApp(from: url)
    }

    nonisolated static func catalogApp(from url: URL) -> CatalogApp? {
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

    nonisolated private static func infoDictionary(forAppAt url: URL) -> [String: Any]? {
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

    nonisolated private static func appName(from info: [String: Any]?, bundle: Bundle?, url: URL) -> String {
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
            source.setEventHandler {
                Task { @MainActor in
                    AppCatalog.shared.scheduleScan(delay: 0.3)
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            sources.append(source)
        }
    }
}
