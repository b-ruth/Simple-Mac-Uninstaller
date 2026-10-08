import Foundation

/// String helpers shared by the leftover and orphan scanners.
enum Matching {
    private static let strippableExtensions: Set<String> = [
        "plist", "savedstate", "binarycookies", "bom", "log", "sfl", "sfl2", "sfl3", "sfl4", "lockfile",
    ]

    private static let topLevelDomains: Set<String> = [
        "com", "org", "net", "io", "co", "app", "dev", "me", "ai", "sh", "im", "fm", "tv", "cc", "to", "ly",
        "gg", "so", "is", "st", "ws", "la", "xyz", "info", "tech", "pro", "one", "edu", "gov", "eu", "us", "uk",
        "ca", "au", "nz", "de", "fr", "nl", "be", "ch", "at", "it", "es", "se", "no", "dk", "fi", "pl", "cz",
        "ru", "cn", "jp", "kr", "tw", "hk", "in", "br", "mx", "software", "design", "studio",
    ]

    /// File name without the extensions macOS appends to bundle identifiers ("com.foo.App.plist").
    static func stem(_ name: String) -> String {
        var result = name as NSString
        while strippableExtensions.contains(result.pathExtension.lowercased()) {
            result = result.deletingPathExtension as NSString
        }
        return result as String
    }

    /// Lowercased letters and digits only, so "Foo Bar", "foo-bar" and "FooBar" compare equal.
    static func normalized(_ string: String) -> String {
        String(string.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    static func isBundleIDLike(_ string: String) -> Bool {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, topLevelDomains.contains(parts[0].lowercased()) else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
            }
        }
    }

    /// Splits "ABCDE12345.group.foo" into the 10-character team ID and the rest.
    static func splitTeamPrefix(_ string: String) -> (team: String?, rest: String) {
        let parts = string.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 10,
              parts[0].unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0) })
        else { return (nil, string) }
        return (String(parts[0]), String(parts[1]))
    }

    /// The forms a bundle identifier takes on disk, lowercased: as is, without a team prefix,
    /// and without a "group." prefix.
    static func identifierVariants(_ stem: String) -> [String] {
        var variants = [stem]
        let (team, rest) = splitTeamPrefix(stem)
        if team != nil { variants.append(rest) }
        for variant in variants where variant.lowercased().hasPrefix("group.") {
            variants.append(String(variant.dropFirst("group.".count)))
        }
        var seen = Set<String>()
        return variants.map { $0.lowercased() }.filter { seen.insert($0).inserted }
    }

    /// "com.google.chrome.helper" -> "com.google"
    static func vendorPrefix(_ bundleID: String) -> String? {
        let parts = bundleID.split(separator: ".")
        return parts.count >= 2 ? parts.prefix(2).joined(separator: ".") : nil
    }

    /// "com.google.chrome" -> "google"
    static func vendorToken(_ bundleID: String) -> String? {
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let token = normalized(String(parts[1]))
        return token.count >= 3 ? token : nil
    }

    /// Sandboxed container folders carry their real identifier in a metadata plist.
    static func containerIdentifier(_ url: URL) -> String? {
        let metadata = url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        return (NSDictionary(contentsOf: metadata) as? [String: Any])?["MCMMetadataIdentifier"] as? String
    }

    /// The executable a launchd plist starts, if it names one.
    static func launchProgram(_ url: URL) -> String? {
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        return dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first
    }
}

enum FileSize {
    static func of(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        func allocated(_ url: URL) -> Int64 {
            let values = try? url.resourceValues(forKeys: keys)
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }

        var total = allocated(url)
        guard (try? url.resourceValues(forKeys: keys))?.isDirectory == true,
              let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                              options: [], errorHandler: { _, _ in true })
        else { return total }
        for case let child as URL in enumerator {
            total += allocated(child)
        }
        return total
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Fills in size and modification date for each item, a few at a time.
    static func measure(_ items: [FoundItem]) async -> [FoundItem] {
        await withTaskGroup(of: (Int, Int64, Date?).self) { group in
            var result = items
            var next = 0
            func addNext() {
                guard next < items.count else { return }
                let index = next, url = items[next].url
                next += 1
                group.addTask {
                    let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    return (index, FileSize.of(url), modified)
                }
            }
            for _ in 0..<8 { addNext() }
            for await (index, size, modified) in group {
                result[index].size = size
                result[index].modified = modified
                addNext()
            }
            return result
        }
    }
}

extension URL {
    /// Path with the home folder shortened to "~".
    var displayPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
