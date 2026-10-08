import SwiftUI

struct ApplicationsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var sortBySize = false

    private var visibleApps: [InstalledApp] {
        let filtered = search.isEmpty ? model.apps : model.apps.filter {
            $0.name.localizedCaseInsensitiveContains(search) || ($0.bundleID ?? "").localizedCaseInsensitiveContains(search)
        }
        guard sortBySize else { return filtered }
        return filtered.sorted { (model.appSizes[$0.url] ?? 0) > (model.appSizes[$1.url] ?? 0) }
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Picker("Sort by", selection: $sortBySize) {
                    Text("Name").tag(false)
                    Text("Size").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                Divider()
                List(visibleApps, selection: $model.selectedAppID) { app in
                    AppRow(app: app, size: model.appSizes[app.url])
                }
                .overlay {
                    if model.isLoadingApps && model.apps.isEmpty {
                        ProgressView("Finding applications…")
                    }
                }
            }
            .frame(width: 310)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: { $0.pathExtension.lowercased() == "app" }) else { return false }
                model.addApp(at: url)
                return true
            }

            Divider()

            Group {
                if let app = model.selectedApp {
                    AppDetailView(app: app)
                } else {
                    ContentUnavailableView("Select an Application", systemImage: "trash",
                                           description: Text("Pick an app from the list, or drop one here, to see everything it has installed."))
                }
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $search, prompt: "Search applications")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.loadApps() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload the application list")
            }
        }
        .navigationTitle("Applications")
        .navigationSubtitle("\(model.apps.count) installed")
        .onChange(of: model.selectedAppID) {
            model.scanSelectedApp()
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let size: Int64?

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(app.version.map { "Version \($0)" } ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let size {
                Text(FileSize.format(size))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AppDetailView: View {
    @Environment(AppModel.self) private var model
    let app: InstalledApp
    @State private var isConfirming = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Divider()
            if model.isScanningLeftovers {
                ProgressView("Scanning for files belonging to \(app.name)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ItemsList(items: model.leftoverItems, selection: $model.leftoverSelection) { confidence in
                    switch confidence {
                    case .high: ConfidenceBadge(label: "Exact", color: .green)
                    case .medium: ConfidenceBadge(label: "By name", color: .blue)
                    case .low: ConfidenceBadge(label: "Maybe", color: .orange)
                    }
                }
            }
            Divider()
            ActionBar(items: model.leftoverItems, selection: $model.leftoverSelection,
                      actionTitle: "Uninstall…", isBusy: model.isRemoving || model.isScanningLeftovers) {
                isConfirming = true
            }
        }
        .confirmationDialog("Uninstall \(app.name)?", isPresented: $isConfirming) {
            Button("Move \(model.leftoverSelection.count) Items to Trash", role: .destructive) {
                Task { await model.uninstallSelectedApp() }
            }
        } message: {
            Text(Remover.isRunning(app) && model.leftoverSelection.contains(app.url)
                 ? "\(app.name) is running and will be quit first. Everything selected is moved to the Trash, where you can still recover it."
                 : "Everything selected is moved to the Trash, where you can still recover it.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.title2.weight(.semibold))
                Text([app.version.map { "Version \($0)" }, app.bundleID].compactMap { $0 }.joined(separator: "  ·  "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(app.url.displayPath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Rescan") { model.scanSelectedApp() }
                .disabled(model.isScanningLeftovers)
        }
        .padding(14)
    }
}
