import ReplaceKitCore
import SwiftUI

struct DiffPreviewView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(source?.title ?? "Review Changes")
                .font(.title2)
            Text(source?.description ?? "Review these changes before applying them.")
                .foregroundStyle(.secondary)
            Text("ReplaceKit will create a snapshot before applying the confirmed changes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let diff = model.pendingDiff {
                HStack(spacing: 12) {
                    ChangeCountBadge(title: "Added", count: diff.added.count, color: .green)
                    ChangeCountBadge(title: "Edited", count: diff.edited.count, color: .blue)
                    ChangeCountBadge(title: "Deleted", count: diff.deleted.count, color: .red)
                    Spacer()
                }

                List {
                    diffSection("Added", replacements: diff.added, color: .green)
                    if !diff.edited.isEmpty {
                        Section("Edited") {
                            ForEach(diff.edited, id: \.after.shortcut) { edited in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(edited.after.shortcut)
                                        .font(.headline.monospaced())

                                    Text("Before")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(edited.before.phrase)
                                        .strikethrough()
                                        .foregroundStyle(.secondary)

                                    Text("After")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(edited.after.phrase)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    diffSection("Deleted", replacements: diff.deleted, color: .red)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    model.cancelPendingBulkApply()
                }
                .disabled(model.isBusy)

                Button {
                    Task { await model.confirmPendingBulkApply() }
                } label: {
                    HStack {
                        if model.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(model.isBusy ? "Applying..." : (source?.confirmationTitle ?? "Apply Changes"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
            }
        }
        .padding()
        .frame(minWidth: 680, minHeight: 480)
    }

    private var source: BulkEditSource? {
        model.pendingBulkEdit?.source
    }

    @ViewBuilder
    private func diffSection(
        _ title: String,
        replacements: [TextReplacement],
        color: Color
    ) -> some View {
        if !replacements.isEmpty {
            Section(title) {
                ForEach(replacements) { replacement in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(replacement.shortcut)
                            .font(.headline.monospaced())
                            .foregroundStyle(color)
                        Text(replacement.phrase)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct ChangeCountBadge: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(.title3)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
        }
        .foregroundStyle(color)
        .frame(minWidth: 72, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
