import SwiftUI

struct HistoryView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Backup History")
                        .font(.title2)
                    Text("Review snapshots before restoring them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Back Up Now") {
                    model.backUpNow()
                }
                .disabled(model.isBusy)
            }
            .padding()

            Divider()

            if model.snapshots.isEmpty {
                ContentUnavailableView(
                    "No snapshots yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(emptyStateDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.snapshots) { snapshot in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snapshot.metadata.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(.headline)
                            Text(snapshot.metadata.reason.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(snapshot.plistURL.lastPathComponent)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Review Restore") {
                            model.previewRestore(snapshot)
                        }
                        .disabled(model.isBusy)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("History")
        .onAppear {
            model.loadHistory()
        }
    }

    private var emptyStateDescription: String {
        if model.backupFolder == nil {
            return "Choose a backup folder, then create your first backup."
        }
        return "Create your first backup to start a restore history."
    }
}
