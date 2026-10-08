import Foundation

// Diagnostic modes that print scan results without opening a window or removing anything:
//   Uninstaller --list-apps
//   Uninstaller --scan /Applications/Some.app
//   Uninstaller --orphans
let arguments = CommandLine.arguments.dropFirst()

func printItems(_ items: [FoundItem]) {
    let labels: [Confidence: String] = [.high: "HIGH", .medium: "MED ", .low: "LOW "]
    for item in items.sorted(by: { ($0.category.rawValue, $0.url.path) < ($1.category.rawValue, $1.url.path) }) {
        print("\(labels[item.confidence]!)  \(FileSize.format(item.size).padding(toLength: 10, withPad: " ", startingAt: 0))  \(item.url.displayPath)\n          \(item.category.rawValue) - \(item.reason)")
    }
    print("\(items.count) items, \(FileSize.format(items.reduce(0) { $0 + $1.size }))")
}

if let mode = arguments.first, mode.hasPrefix("--"), ["--list-apps", "--scan", "--orphans"].contains(mode) {
    Task {
        let apps = await AppDiscovery.discover()
        switch mode {
        case "--list-apps":
            for app in apps {
                print("\(app.name)  [\(app.bundleID ?? "-")]  team=\(app.teamID ?? "-")  nested=\(app.nestedBundleIDs.count)  \(app.url.path)")
            }
        case "--scan":
            let path = arguments.dropFirst().first ?? ""
            let url = URL(fileURLWithPath: path)
            if let app = apps.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) ?? AppDiscovery.load(url) {
                printItems(await LeftoverScanner().scan(app: app, allApps: apps))
            } else {
                print("Not an application: \(path)")
            }
        default:
            printItems(await OrphanScanner().scan(apps: apps, ignoredPaths: []))
        }
        exit(0)
    }
    dispatchMain()
} else {
    UninstallerApp.main()
}
