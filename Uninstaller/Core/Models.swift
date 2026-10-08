import Foundation

struct InstalledApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    let teamID: String?
    /// Every name the app goes by: file name, CFBundleName, display name, executable.
    let aliases: [String]
    /// Bundle identifiers of helpers, XPC services, extensions and frameworks inside the bundle.
    let nestedBundleIDs: Set<String>

    var id: URL { url }
}

enum ItemCategory: String, CaseIterable {
    case application = "Application"
    case appSupport = "Application Support"
    case caches = "Caches"
    case preferences = "Preferences"
    case containers = "Containers"
    case savedState = "Saved State"
    case webData = "Web Data & Cookies"
    case logs = "Logs & Crash Reports"
    case launchItems = "Launch Agents & Daemons"
    case helpers = "Privileged Helpers"
    case receipts = "Installer Receipts"
    case temporary = "Temporary Files"
}

enum Confidence: Int, Comparable {
    case low, medium, high

    static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct FoundItem: Identifiable, Hashable {
    let url: URL
    let category: ItemCategory
    let confidence: Confidence
    let reason: String
    let isDirectory: Bool
    var size: Int64 = 0
    var modified: Date?

    var id: URL { url }
}

struct RemovalReport: Identifiable {
    struct Failure: Identifiable {
        let url: URL
        let message: String
        var id: URL { url }
    }

    let id = UUID()
    var removed: [URL] = []
    var failed: [Failure] = []
}
