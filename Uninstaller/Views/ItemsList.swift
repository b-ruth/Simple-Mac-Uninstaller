import SwiftUI

struct ConfidenceBadge {
    let label: String
    let color: Color
}

/// Checklist of found files grouped by category; shared by the uninstall and orphan screens.
struct ItemsList: View {
    let items: [FoundItem]
    @Binding var selection: Set<URL>
    let badge: (Confidence) -> ConfidenceBadge
    var onIgnore: ((FoundItem) -> Void)?

    private var groups: [(category: ItemCategory, items: [FoundItem])] {
        ItemCategory.allCases.compactMap { category in
            let matching = items.filter { $0.category == category }
                .sorted { ($0.confidence, $0.size) > ($1.confidence, $1.size) }
            return matching.isEmpty ? nil : (category, matching)
        }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.category) { group in
                Section {
                    ForEach(group.items) { item in
                        row(item)
                    }
                } header: {
                    HStack {
                        Text(group.category.rawValue)
                        Spacer()
                        Text(FileSize.format(group.items.reduce(0) { $0 + $1.size }))
                            .monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func row(_ item: FoundItem) -> some View {
        let badge = badge(item.confidence)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selection.contains(item.url) },
                set: { isOn in
                    if isOn { selection.insert(item.url) } else { selection.remove(item.url) }
                }))
                .labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.displayPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.url.path)
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let modified = item.modified {
                Text(modified, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Last modified")
            }
            Text(badge.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badge.color.opacity(0.18), in: Capsule())
                .foregroundStyle(badge.color)
            Text(FileSize.format(item.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            if let onIgnore {
                Button("Ignore This Item") { onIgnore(item) }
            }
        }
    }
}

/// Bottom bar with the selection summary and the destructive action.
struct ActionBar: View {
    let items: [FoundItem]
    @Binding var selection: Set<URL>
    let actionTitle: String
    let isBusy: Bool
    let action: () -> Void

    private var selectedSize: Int64 {
        items.filter { selection.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        HStack(spacing: 12) {
            Menu("Select") {
                Button("All") { selection = Set(items.map(\.url)) }
                Button("Confident Matches Only") {
                    selection = Set(items.filter { $0.confidence == .high }.map(\.url))
                }
                Button("None") { selection = [] }
            }
            .fixedSize()
            Text("\(selection.count) of \(items.count) selected, \(FileSize.format(selectedSize))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
            Button(actionTitle, role: .destructive, action: action)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selection.isEmpty || isBusy)
        }
        .padding(12)
        .background(.bar)
    }
}
