import SwiftUI

enum SidebarSection: Hashable {
    case applications, orphans
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var section: SidebarSection = .applications

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                if !model.hasFullDiskAccess {
                    FullDiskAccessBanner()
                }
                switch section {
                case .applications: ApplicationsView()
                case .orphans: OrphansView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $section) {
                        Text("Applications").tag(SidebarSection.applications)
                        Text(model.orphanItems.isEmpty ? "Orphaned Files" : "Orphaned Files (\(model.orphanItems.count))")
                            .tag(SidebarSection.orphans)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkFullDiskAccess()
        }
        .sheet(item: $model.removalReport) { report in
            RemovalReportView(report: report)
        }
    }
}

struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Full Disk Access is off, so macOS hides some app data from scans.")
                .font(.callout)
            Spacer()
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.12))
    }
}

struct RemovalReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let report: RemovalReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: report.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(report.failed.isEmpty ? .green : .orange)
                VStack(alignment: .leading) {
                    Text("\(report.removed.count) item\(report.removed.count == 1 ? "" : "s") moved to the Trash")
                        .font(.headline)
                    if !report.failed.isEmpty {
                        Text("\(report.failed.count) could not be moved")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !report.failed.isEmpty {
                List(report.failed) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.url.displayPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("These usually belong to the system administrator. Finder can move them after asking for your password.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if model.isRemoving { ProgressView().controlSize(.small) }
                Spacer()
                if !report.failed.isEmpty {
                    Button("Retry as Administrator") {
                        Task { await model.retryWithAdministrator(report) }
                    }
                    .disabled(model.isRemoving)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
