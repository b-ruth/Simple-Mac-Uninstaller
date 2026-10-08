import AppKit

/// Finds files in the Library folders that no installed app accounts for.
///
/// Confidence here means: `.high` nothing installed matches at all, `.medium` the item is
/// unclaimed but something related (same developer, loosely similar name) is still around.
struct OrphanScanner {
    func scan(apps: [InstalledApp], ignoredPaths: Set<String>) async -> [FoundItem] {
        let index = Index(apps: apps)
        var items: [FoundItem] = []

        for location in Locations.all where location.orphanScan {
            if Task.isCancelled { return [] }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: location.url, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
            for child in children {
                guard !ignoredPaths.contains(child.path), Safety.canRemove(child) else { continue }
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if let verdict = index.verdict(for: child, isDirectory: isDirectory, in: location) {
                    items.append(FoundItem(url: child, category: location.category, confidence: verdict.0,
                                           reason: verdict.1, isDirectory: isDirectory))
                }
            }
        }

        if Task.isCancelled { return [] }
        return await FileSize.measure(items)
    }
}

private struct Index {
    var ids = Set<String>()
    /// Every dotted prefix of every installed identifier ("com.foo", "com.foo.suite", ...).
    var idPrefixes = Set<String>()
    var vendorPrefixes = Set<String>()
    var names = Set<String>()
    var teamIDs = Set<String>()

    init(apps: [InstalledApp]) {
        for app in apps {
            let all = ([app.bundleID].compactMap { $0 } + app.nestedBundleIDs).map { $0.lowercased() }
            for id in all {
                ids.insert(id)
                let parts = id.split(separator: ".")
                if parts.count >= 2 {
                    for count in 2...parts.count {
                        idPrefixes.insert(parts.prefix(count).joined(separator: "."))
                    }
                }
                if let last = parts.last { names.insert(Matching.normalized(String(last))) }
            }
            if let id = app.bundleID?.lowercased() {
                if let vendor = Matching.vendorPrefix(id) { vendorPrefixes.insert(vendor) }
                if let token = Matching.vendorToken(id) { names.insert(token) }
            }
            for alias in app.aliases { names.insert(Matching.normalized(alias)) }
            if let teamID = app.teamID { teamIDs.insert(teamID) }
        }
        names.formUnion(AppDiscovery.systemComponentNames())
        names = names.filter { $0.count >= 3 }
    }

    func verdict(for url: URL, isDirectory: Bool, in location: ScanLocation) -> (Confidence, String)? {
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return nil }

        if location.category == .launchItems {
            return launchItemVerdict(url)
        }

        var stem = Matching.stem(name)
        if location.category == .containers, let identifier = Matching.containerIdentifier(url) {
            stem = identifier
        }
        let (team, rest) = Matching.splitTeamPrefix(stem)
        if let team, teamIDs.contains(team) { return nil }

        let variants = Matching.identifierVariants(stem)
        if variants.contains(where: Matching.isBundleIDLike) {
            return identifierVerdict(variants)
        }
        if rest.lowercased().hasPrefix("group.") { return nil }

        // Folders named after an app rather than its identifier. Far less reliable, so
        // only in the places apps normally create them, and never better than "possible".
        guard isDirectory, team == nil, [.appSupport, .caches, .logs].contains(location.category),
              location.category == .appSupport || !location.url.path.hasPrefix("/Library/") else { return nil }
        let normalized = Matching.normalized(name)
        guard normalized.count >= 3, !Self.knownSystemNames.contains(normalized),
              !normalized.hasPrefix("apple"), !normalized.hasPrefix("comapple") else { return nil }
        if names.contains(normalized) { return nil }
        if names.contains(where: { $0.count >= 4 && (normalized.contains($0) || (normalized.count >= 4 && $0.contains(normalized))) }) {
            return nil
        }
        return (.medium, "No installed app is named \"\(name)\"")
    }

    private func identifierVerdict(_ variants: [String]) -> (Confidence, String)? {
        for variant in variants {
            if Self.systemIdentifierPrefixes.contains(where: variant.hasPrefix) { return nil }
            if idPrefixes.contains(variant) { return nil }
            for candidate in truncations(of: variant) {
                if ids.contains(candidate) || launchServicesKnows(candidate) { return nil }
            }
        }
        guard let identifier = variants.last, let vendor = Matching.vendorPrefix(identifier) else { return nil }
        if vendorPrefixes.contains(vendor) || Matching.vendorToken(identifier).map(names.contains) == true {
            return (.medium, "No installed app uses \(identifier), but other \(vendor) software is installed")
        }
        return (.high, "No installed app uses \(identifier)")
    }

    private func launchItemVerdict(_ url: URL) -> (Confidence, String)? {
        guard url.pathExtension == "plist", !url.lastPathComponent.hasPrefix("com.apple."),
              let program = Matching.launchProgram(url), program.hasPrefix("/"),
              !FileManager.default.fileExists(atPath: program) else { return nil }
        return (.high, "Starts a program that no longer exists: \(program)")
    }

    /// "a.b.c.d" -> ["a.b.c.d", "a.b.c"]: the identifier itself and its parents down to three parts.
    private func truncations(of identifier: String) -> [String] {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 3 else { return [identifier] }
        return (3...parts.count).reversed().map { parts.prefix($0).joined(separator: ".") }
    }

    /// Catches apps living outside the Applications folders (external disks, Downloads, ...).
    private func launchServicesKnows(_ identifier: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return false }
        return !url.path.contains("/.Trash/") && FileManager.default.fileExists(atPath: url.path)
    }

    /// Identifiers used by macOS itself and by developer toolchains.
    private static let systemIdentifierPrefixes = [
        "com.apple.", "apple.", "is.workflow.", "org.cups.", "org.swift.", "io.sentry", "io.branch", "com.crashlytics",
    ]

    /// Folders created by macOS itself or by command-line tools rather than by apps.
    private static let knownSystemNames: Set<String> = [
        "addressbook", "callhistorydb", "callhistorytransactions", "clouddocs", "knowledge", "fileprovider",
        "icloud", "icdd", "syncservices", "crashreporter", "diskimages", "mobilesync", "networkserviceproxy",
        "accessibility", "animoji", "assistant", "differentialprivacy", "default", "discrecording", "coreparsec",
        "contactsd", "familycircle", "geoservices", "homeenergyd", "identityservices", "locationaccessstored",
        "privatecloudcomputed", "stickers", "tipsd", "transparencyd", "videosubscriptionsd", "gamekit", "passkit",
        "siri", "askpermissiond", "cloudkit", "controlcenter", "diagnosticreports", "diagnosticmessages",
        "coresimulator", "dnssd", "icloudmailagent", "mbsetupuser", "metadata", "sesstorage", "tccd", "trial",
        "homebrew", "pip", "typescript", "node", "npm", "yarn", "gobuild", "msplaywright", "pypoetry",
        "cocoapods", "swiftpm", "clang", "carthage", "jedi", "pnpm", "bun", "deno", "electron", "puppeteer",
        "configurationprofiles", "familiar", "interactions", "audio", "automator", "colorsync", "dictionaries",
        "screenrecordings", "storekit", "syncedpreferences", "weather", "virtualization", "keyboardservices",
        "btserver", "amsdatamigratortool", "mbuseragent", "privacypreservingmeasurement", "ilifemediabrowser", "desktoppictures", "windowserver", "xsan", "baseband", "nodegyp",
        "iosentry", "iobranch", "sentrycrash", "jna", "cef", "flutterengine", "velopack", "kotlin", "gradle",
        "coreaudio", "cups", "geod", "passd", "mds", "ocsp", "gamekit", "byhost", "systemextensions",
    ]
}
