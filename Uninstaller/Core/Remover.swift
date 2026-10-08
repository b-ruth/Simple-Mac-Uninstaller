import AppKit

/// Everything is moved to the Trash, never deleted outright, so a wrong guess can be undone.
enum Remover {
    static func trash(_ urls: [URL]) async -> RemovalReport {
        var report = RemovalReport()
        // Deepest paths first, so a folder and something inside it can both be selected.
        for url in urls.sorted(by: { $0.path.count > $1.path.count }) {
            guard Safety.canRemove(url) else {
                report.failed.append(.init(url: url, message: "Refused: outside the locations Uninstaller manages"))
                continue
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                report.removed.append(url)
                continue
            }
            unloadIfLaunchAgent(url)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                report.removed.append(url)
            } catch {
                report.failed.append(.init(url: url, message: error.localizedDescription))
            }
        }
        return report
    }

    /// Second attempt for root-owned items: Finder moves them to the Trash after asking
    /// for an administrator password itself.
    static func trashWithFinder(_ urls: [URL]) async -> RemovalReport {
        let allowed = urls.filter(Safety.canRemove)
        let list = allowed.map { "POSIX file \"\(escape($0.path))\"" }.joined(separator: ", ")
        var errorText = ""
        if !allowed.isEmpty {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application \"Finder\" to delete {\(list)}"]
            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = Pipe()
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                errorText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } catch {
                errorText = error.localizedDescription
            }
        }

        var report = RemovalReport()
        for url in urls {
            if !FileManager.default.fileExists(atPath: url.path) {
                report.removed.append(url)
            } else {
                report.failed.append(.init(url: url, message: errorText.isEmpty ? "Still present after asking Finder" : errorText))
            }
        }
        return report
    }

    /// Asks the app to quit, waits briefly, then forces it.
    @MainActor
    static func quit(_ app: InstalledApp) async {
        guard let bundleID = app.bundleID else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL }
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        for _ in 0..<20 where running.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    static func isRunning(_ app: InstalledApp) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func unloadIfLaunchAgent(_ url: URL) {
        let userAgents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path
        guard url.pathExtension == "plist", url.deletingLastPathComponent().path == userAgents else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", url.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    private static func escape(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
