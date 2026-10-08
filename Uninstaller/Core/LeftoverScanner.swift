import Foundation

/// Finds everything a specific app has scattered around the system.
struct LeftoverScanner {
    func scan(app: InstalledApp, allApps: [InstalledApp]) async -> [FoundItem] {
        let identity = Identity(app: app, allApps: allApps)
        var items = [FoundItem(url: app.url, category: .application, confidence: .high,
                               reason: "The application itself", isDirectory: true)]
        var seen: Set<String> = [app.url.standardizedFileURL.path]

        func add(_ url: URL, _ location: ScanLocation, _ match: (Confidence, String), isDirectory: Bool) {
            guard Safety.canRemove(url), seen.insert(url.standardizedFileURL.path).inserted else { return }
            items.append(FoundItem(url: url, category: location.category, confidence: match.0,
                                   reason: match.1, isDirectory: isDirectory))
        }

        for location in Locations.all {
            if Task.isCancelled { return [] }
            for child in children(of: location.url) {
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if let match = identity.match(child, in: location) {
                    add(child, location, match, isDirectory: isDirectory)
                } else if isDirectory, identity.isVendorFolder(child, in: location) {
                    // "~/Library/Application Support/Google/Chrome": look inside the vendor's folder.
                    for grandchild in children(of: child) where identity.names.contains(Matching.normalized(Matching.stem(grandchild.lastPathComponent))) {
                        let isDir = (try? grandchild.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                        add(grandchild, location, (.medium, "Matches the app name inside the developer's folder"), isDirectory: isDir)
                    }
                }
            }
        }

        if Task.isCancelled { return [] }
        return await FileSize.measure(items)
    }

    private func children(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
    }
}

private struct Identity {
    let appPath: String
    let bundleIDs: [String]
    let names: Set<String>
    let rawNames: [String]
    let teamID: String?
    let vendorToken: String?
    /// Identifiers of other installed apps, so "com.foo.app" never claims "com.foo.app.beta"'s files.
    let otherAppIDs: [String]

    init(app: InstalledApp, allApps: [InstalledApp]) {
        appPath = app.url.path
        let main = app.bundleID?.lowercased()
        var ids = main.map { [$0] } ?? []
        if let main, let vendor = Matching.vendorPrefix(main) {
            // Helpers count only when they share the app's vendor: embedded third-party
            // frameworks (Sparkle, Electron) are not this app's data.
            ids += app.nestedBundleIDs.map { $0.lowercased() }
                .filter { $0 != main && $0.hasPrefix(vendor + ".") }
                .sorted()
        }
        bundleIDs = ids
        rawNames = app.aliases.filter { $0.count >= 3 }.map { $0.lowercased() }
        names = Set(app.aliases.map(Matching.normalized).filter { $0.count >= 3 })
        teamID = app.teamID
        vendorToken = main.flatMap(Matching.vendorToken)
        otherAppIDs = allApps.filter { $0.url != app.url }.compactMap { $0.bundleID?.lowercased() }
            .filter { !ids.contains($0) }
    }

    func match(_ url: URL, in location: ScanLocation) -> (Confidence, String)? {
        let name = url.lastPathComponent
        if name.hasPrefix(".") && location.category != .containers { return nil }
        var stem = Matching.stem(name)
        if location.category == .containers, let identifier = Matching.containerIdentifier(url) {
            stem = identifier
        }
        let variants = Matching.identifierVariants(stem)

        for id in bundleIDs {
            for variant in variants where variant == id || variant.hasPrefix(id + ".") {
                let claimedElsewhere = otherAppIDs.contains {
                    $0.count > id.count && (variant == $0 || variant.hasPrefix($0 + "."))
                }
                if !claimedElsewhere {
                    return (.high, "Matches bundle identifier \(id)")
                }
            }
        }

        if location.category == .launchItems, url.pathExtension == "plist",
           let program = Matching.launchProgram(url), program.hasPrefix(appPath + "/") {
            return (.high, "Launches a helper inside the app")
        }

        let normalized = Matching.normalized(stem)
        if names.contains(normalized) {
            return (.medium, "Matches the app name")
        }

        if location.matchNamePrefix {
            let lowered = name.lowercased()
            if rawNames.contains(where: { lowered.hasPrefix($0 + "_") || lowered.hasPrefix($0 + "-20") }) {
                return (.medium, "Report file named after the app")
            }
            return nil
        }

        if let teamID, Matching.splitTeamPrefix(stem).team == teamID {
            return (.low, "Group container shared by this developer's apps")
        }
        if !Matching.isBundleIDLike(stem), let hit = names.first(where: { $0.count >= 5 && normalized.contains($0) }) {
            return (.low, "Name contains \"\(hit)\"")
        }
        return nil
    }

    func isVendorFolder(_ url: URL, in location: ScanLocation) -> Bool {
        guard let vendorToken, [.appSupport, .caches, .logs].contains(location.category) else { return false }
        return Matching.normalized(url.lastPathComponent) == vendorToken
    }
}
