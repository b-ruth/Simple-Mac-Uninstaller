import SwiftUI

struct OrphansView: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirming = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if model.isScanningOrphans {
                ProgressView("Comparing Library folders against installed applications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.hasScannedOrphans {
                ContentUnavailableView {
                    Label("Find Orphaned Files", systemImage: "questionmark.folder")
                } description: {
                    Text("Looks through the Library folders for files left behind by apps that were dragged to the Trash. Nothing is removed until you choose it.")
                } actions: {
                    Button("Scan") { Task { await model.scanOrphans() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if model.orphanItems.isEmpty {
                ContentUnavailableView("No Orphaned Files Found", systemImage: "checkmark.circle",
                                       description: Text("Everything in the scanned folders belongs to an installed app."))
            } else {
                Text("These are educated guesses. \"Likely\" means no installed app matches at all; \"Possible\" items may belong to command-line tools, plug-ins or apps stored elsewhere. Check before removing, and right-click anything you want to keep out of future scans.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                Divider()
                ItemsList(items: model.orphanItems, selection: $model.orphanSelection, badge: { confidence in
                    confidence == .high ? ConfidenceBadge(label: "Likely", color: .green)
                                        : ConfidenceBadge(label: "Possible", color: .orange)
                }, onIgnore: { model.ignoreOrphan($0) })
                Divider()
                ActionBar(items: model.orphanItems, selection: $model.orphanSelection,
                          actionTitle: "Move to Trash…", isBusy: model.isRemoving) {
                    isConfirming = true
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if !model.ignoredPaths.isEmpty {
                    Button("Reset Ignored") {
                        model.resetIgnoredOrphans()
                        Task { await model.scanOrphans() }
                    }
                    .help("Show items you previously chose to ignore")
                }
                Button {
                    Task { await model.scanOrphans() }
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanningOrphans)
                .help("Scan for orphaned files")
            }
        }
        .navigationTitle("Orphaned Files")
        .navigationSubtitle(model.hasScannedOrphans
                            ? "\(model.orphanItems.count) found, \(FileSize.format(model.orphanItems.reduce(0) { $0 + $1.size }))"
                            : "")
        .confirmationDialog("Move \(model.orphanSelection.count) items to the Trash?", isPresented: $isConfirming) {
            Button("Move to Trash", role: .destructive) {
                Task { await model.removeSelectedOrphans() }
            }
        } message: {
            Text("They stay in the Trash until you empty it, so you can put back anything an app turns out to need.")
        }
    }
}
