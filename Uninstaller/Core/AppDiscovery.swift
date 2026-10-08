import Foundation
import Security

enum AppDiscovery {
    private static var searchRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    /// Third-party and removable apps, sorted by name. Apps under /System are left out
    /// because macOS does not allow removing them.
    static func discover() async -> [InstalledApp] {
        var bundles: [URL] = []
        for root in searchRoots {
            collectApps(in: root, depth: 2, into: &bundles)
        }
        let own = Bundle.main.bundleURL.standardizedFileURL

        let apps = await withTaskGroup(of: InstalledApp?.self) { group in
            for url in bundles where url.standardizedFileURL != own {
                group.addTask { load(url) }
            }
            var result: [InstalledApp] = []
            for await app in group {
                if let app { result.append(app) }
            }
            return result
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func load(_ url: URL) -> InstalledApp? {
        // Safari and friends appear in /Applications as links into the sealed system volume.
        let resolved = url.resolvingSymlinksInPath()
        guard !resolved.path.hasPrefix("/System/"),
              let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        else { return nil }

        let fileName = url.deletingPathExtension().lastPathComponent
        var aliases = [fileName]
        for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
            if let value = info[key] as? String, !aliases.contains(value) { aliases.append(value) }
        }

        var nested = Set<String>()
        collectNestedBundleIDs(in: url.appendingPathComponent("Contents"), depth: 5, into: &nested)

        return InstalledApp(
            url: url,
            name: fileName,
            bundleID: info["CFBundleIdentifier"] as? String,
            // Some apps put the word in the string itself ("Version 2.0").
            version: (info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String)?
                .replacingOccurrences(of: "^version\\s*", with: "", options: [.regularExpression, .caseInsensitive]),
            teamID: teamID(of: url),
            aliases: aliases,
            nestedBundleIDs: nested
        )
    }

    /// Normalized names of the apps, frameworks and daemons that ship with macOS, so the
    /// orphan scan never flags their data.
    static func systemComponentNames() -> Set<String> {
        var names = Set<String>()
        for path in ["/System/Applications", "/System/Applications/Utilities", "/System/Library/CoreServices",
                     "/System/Library/CoreServices/Applications", "/System/Library/Frameworks",
                     "/System/Library/PrivateFrameworks", "/usr/libexec", "/usr/sbin", "/usr/bin"] {
            let children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            for child in children {
                names.insert(Matching.normalized((child as NSString).deletingPathExtension))
            }
        }
        return names
    }

    private static func collectApps(in directory: URL, depth: Int, into bundles: inout [URL]) {
        guard depth > 0, let children = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        for child in children {
            if child.pathExtension.lowercased() == "app" {
                bundles.append(child)
            } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                collectApps(in: child, depth: depth - 1, into: &bundles)
            }
        }
    }

    private static let bundleExtensions: Set<String> = ["app", "xpc", "appex", "framework", "bundle", "systemextension", "plugin"]
    private static let skippedDirectories: Set<String> = ["Resources", "Headers", "Modules", "_CodeSignature", "SharedSupport", "Developer"]

    private static func collectNestedBundleIDs(in directory: URL, depth: Int, into ids: inout Set<String>) {
        guard depth > 0, let children = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { return }
        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }

            if bundleExtensions.contains(child.pathExtension.lowercased()) {
                for plist in ["Contents/Info.plist", "Resources/Info.plist", "Versions/Current/Resources/Info.plist", "Info.plist"] {
                    if let info = NSDictionary(contentsOf: child.appendingPathComponent(plist)) as? [String: Any],
                       let id = info["CFBundleIdentifier"] as? String {
                        ids.insert(id)
                        break
                    }
                }
                collectNestedBundleIDs(in: child, depth: depth - 1, into: &ids)
            } else if directory.lastPathComponent == "Contents", child.lastPathComponent == "Resources" {
                // Some apps keep a helper .app directly in Resources; look one level, no deeper.
                collectNestedBundleIDs(in: child, depth: 1, into: &ids)
            } else if !skippedDirectories.contains(child.lastPathComponent), child.pathExtension != "lproj" {
                collectNestedBundleIDs(in: child, depth: depth - 1, into: &ids)
            }
        }
    }

    private static func teamID(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
