import ReplaceKitCore
import SwiftUI

struct DiffPreviewView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Changes")
                .font(.title2)
            Text("ReplaceKit will create a snapshot before applying these changes through System Settings.")
                .foregroundStyle(.secondary)

            if let diff = model.pendingDiff {
                List {
                    diffSection("Added", replacements: diff.added, color: .green)
                    if !diff.edited.isEmpty {
                        Section("Edited") {
                            ForEach(diff.edited, id: \.after.shortcut) { edited in
                                VStack(alignment: .leading) {
                                    Text(edited.after.shortcut).font(.headline)
                                    Text(edited.before.phrase).strikethrough().foregroundStyle(.secondary)
                                    Text(edited.after.phrase)
                                }
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
                Button("Apply Changes") {
                    Task { await model.confirmPendingBulkApply() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 680, minHeight: 480)
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
                    VStack(alignment: .leading) {
                        Text(replacement.shortcut)
                            .font(.headline)
                            .foregroundStyle(color)
                        Text(replacement.phrase)
                    }
                }
            }
        }
    }
}
