import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    // Applications
    var apps: [InstalledApp] = []
    var appSizes: [URL: Int64] = [:]
    var isLoadingApps = false
    var selectedAppID: URL?
    var leftoverItems: [FoundItem] = []
    var leftoverSelection: Set<URL> = []
    var isScanningLeftovers = false

    // Orphans
    var orphanItems: [FoundItem] = []
    var orphanSelection: Set<URL> = []
    var isScanningOrphans = false
    var hasScannedOrphans = false

    var isRemoving = false
    var removalReport: RemovalReport?
    var hasFullDiskAccess = true

    private var leftoverScan: Task<Void, Never>?
    private var sizeScan: Task<Void, Never>?
    private static let ignoredKey = "ignoredOrphanPaths"

    var selectedApp: InstalledApp? {
        apps.first { $0.url == selectedAppID }
    }

    var ignoredPaths: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: Self.ignoredKey) }
    }

    func loadApps() async {
        isLoadingApps = true
        checkFullDiskAccess()
        let found = await AppDiscovery.discover()
        apps = found
        isLoadingApps = false
        if selectedApp == nil { selectedAppID = nil }

        sizeScan?.cancel()
        sizeScan = Task {
            for app in found where appSizes[app.url] == nil {
                if Task.isCancelled { return }
                let url = app.url
                appSizes[url] = await Task.detached(priority: .utility) { FileSize.of(url) }.value
            }
        }
    }

    /// An app dropped onto the window from anywhere on disk.
    func addApp(at url: URL) {
        guard url.pathExtension.lowercased() == "app" else { return }
        if !apps.contains(where: { $0.url == url }) {
            guard let app = AppDiscovery.load(url) else { return }
            apps.append(app)
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        selectedAppID = url
    }

    func scanSelectedApp() {
        leftoverScan?.cancel()
        leftoverItems = []
        leftoverSelection = []
        guard let app = selectedApp else {
            isScanningLeftovers = false
            return
        }
        isScanningLeftovers = true
        let allApps = apps
        leftoverScan = Task {
            let items = await LeftoverScanner().scan(app: app, allApps: allApps)
            if Task.isCancelled { return }
            leftoverItems = items
            // Weak matches are shown but left for the user to opt into.
            leftoverSelection = Set(items.filter { $0.confidence > .low }.map(\.url))
            isScanningLeftovers = false
        }
    }

    func uninstallSelectedApp() async {
        guard let app = selectedApp else { return }
        let urls = leftoverItems.map(\.url).filter(leftoverSelection.contains)
        isRemoving = true
        if urls.contains(app.url) { await Remover.quit(app) }
        let report = await Remover.trash(urls)
        isRemoving = false
        apply(report)
        removalReport = report
    }

    func scanOrphans() async {
        isScanningOrphans = true
        orphanSelection = []
        checkFullDiskAccess()
        let allApps = await AppDiscovery.discover()
        orphanItems = await OrphanScanner().scan(apps: allApps, ignoredPaths: ignoredPaths)
        isScanningOrphans = false
        hasScannedOrphans = true
    }

    func removeSelectedOrphans() async {
        let urls = orphanItems.map(\.url).filter(orphanSelection.contains)
        isRemoving = true
        let report = await Remover.trash(urls)
        isRemoving = false
        apply(report)
        removalReport = report
    }

    func retryWithAdministrator(_ report: RemovalReport) async {
        isRemoving = true
        var retried = await Remover.trashWithFinder(report.failed.map(\.url))
        isRemoving = false
        apply(retried)
        retried.removed = report.removed + retried.removed
        removalReport = retried
    }

    func ignoreOrphan(_ item: FoundItem) {
        ignoredPaths.insert(item.url.path)
        orphanItems.removeAll { $0.url == item.url }
        orphanSelection.remove(item.url)
    }

    func resetIgnoredOrphans() {
        ignoredPaths = []
    }

    private func apply(_ report: RemovalReport) {
        let removed = Set(report.removed)
        guard !removed.isEmpty else { return }
        leftoverItems.removeAll { removed.contains($0.url) }
        leftoverSelection.subtract(removed)
        orphanItems.removeAll { removed.contains($0.url) }
        orphanSelection.subtract(removed)
        if let selectedAppID, removed.contains(selectedAppID) {
            self.selectedAppID = nil
            leftoverItems = []
            leftoverSelection = []
        }
        apps.removeAll { removed.contains($0.url) }
    }

    /// Without Full Disk Access macOS hides other apps' containers, so scans come up short.
    /// Granted if any folder that only Full Disk Access unlocks can be listed.
    func checkFullDiskAccess() {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let probes = ["Safari", "Mail", "Messages", "Cookies", "Suggestions"].map { library.appendingPathComponent($0).path }
            + ["/Library/Application Support/com.apple.TCC"]
        hasFullDiskAccess = probes.contains { (try? FileManager.default.contentsOfDirectory(atPath: $0)) != nil }
    }
}
