import Foundation

struct ScanLocation {
    let url: URL
    let category: ItemCategory
    /// Whether the orphan scan looks here. Some places are only worth checking for a specific app.
    var orphanScan = true
    /// Match files that merely start with the app's name (crash reports: "AppName_2026-01-01.ips").
    var matchNamePrefix = false
}

enum Locations {
    static let all: [ScanLocation] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let userLibrary = home.appendingPathComponent("Library")
        let systemLibrary = URL(fileURLWithPath: "/Library")

        var locations: [ScanLocation] = [
            ScanLocation(url: userLibrary.appendingPathComponent("Application Support"), category: .appSupport),
            ScanLocation(url: userLibrary.appendingPathComponent("Application Scripts"), category: .containers),
            ScanLocation(url: userLibrary.appendingPathComponent("Containers"), category: .containers),
            ScanLocation(url: userLibrary.appendingPathComponent("Group Containers"), category: .containers),
            ScanLocation(url: userLibrary.appendingPathComponent("Caches"), category: .caches),
            ScanLocation(url: userLibrary.appendingPathComponent("Preferences"), category: .preferences),
            ScanLocation(url: userLibrary.appendingPathComponent("Preferences/ByHost"), category: .preferences, orphanScan: false),
            ScanLocation(url: userLibrary.appendingPathComponent("Saved Application State"), category: .savedState),
            ScanLocation(url: userLibrary.appendingPathComponent("HTTPStorages"), category: .webData),
            ScanLocation(url: userLibrary.appendingPathComponent("WebKit"), category: .webData),
            ScanLocation(url: userLibrary.appendingPathComponent("Cookies"), category: .webData),
            ScanLocation(url: userLibrary.appendingPathComponent("Logs"), category: .logs),
            ScanLocation(url: userLibrary.appendingPathComponent("Logs/DiagnosticReports"), category: .logs, orphanScan: false, matchNamePrefix: true),
            ScanLocation(url: userLibrary.appendingPathComponent("Application Support/CrashReporter"), category: .logs, orphanScan: false, matchNamePrefix: true),
            ScanLocation(url: userLibrary.appendingPathComponent("LaunchAgents"), category: .launchItems),

            ScanLocation(url: systemLibrary.appendingPathComponent("Application Support"), category: .appSupport),
            ScanLocation(url: systemLibrary.appendingPathComponent("Caches"), category: .caches),
            ScanLocation(url: systemLibrary.appendingPathComponent("Preferences"), category: .preferences),
            ScanLocation(url: systemLibrary.appendingPathComponent("Logs"), category: .logs),
            ScanLocation(url: systemLibrary.appendingPathComponent("Logs/DiagnosticReports"), category: .logs, orphanScan: false, matchNamePrefix: true),
            ScanLocation(url: systemLibrary.appendingPathComponent("LaunchAgents"), category: .launchItems),
            ScanLocation(url: systemLibrary.appendingPathComponent("LaunchDaemons"), category: .launchItems),
            ScanLocation(url: systemLibrary.appendingPathComponent("PrivilegedHelperTools"), category: .helpers),
            ScanLocation(url: URL(fileURLWithPath: "/private/var/db/receipts"), category: .receipts, orphanScan: false),
        ]

        // Per-user temp and cache folders under /var/folders (siblings "T" and "C").
        let temp = FileManager.default.temporaryDirectory.standardizedFileURL
        if temp.lastPathComponent == "T" {
            locations.append(ScanLocation(url: temp, category: .temporary, orphanScan: false))
            locations.append(ScanLocation(url: temp.deletingLastPathComponent().appendingPathComponent("C"),
                                          category: .temporary, orphanScan: false))
        }
        return locations
    }()
}

enum Safety {
    /// Last line of defence before anything is moved to the Trash: only app bundles and
    /// things strictly inside a known scan location qualify, never the locations themselves.
    static func canRemove(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path.hasPrefix("/System/") || url.pathComponents.count < 3 { return false }
        if path == Bundle.main.bundleURL.standardizedFileURL.path { return false }

        let roots = Locations.all.map { $0.url.standardizedFileURL.path }
        if roots.contains(path) { return false }
        if url.pathExtension.lowercased() == "app" { return true }
        return roots.contains { path.hasPrefix($0 + "/") }
    }
}
