import SwiftUI

struct HistoryView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Backup History")
                    .font(.title2)
                Spacer()
                Button("Back Up Now") {
                    model.backUpNow()
                }
            }

            if model.snapshots.isEmpty {
                ContentUnavailableView(
                    "No snapshots yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Choose a folder and create your first backup.")
                )
            } else {
                List(model.snapshots) { snapshot in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(snapshot.metadata.timestamp.formatted(date: .abbreviated, time: .standard))
                            Text(snapshot.metadata.reason.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(snapshot.plistURL.lastPathComponent)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Button("Preview Restore") {
                            model.previewRestore(snapshot)
                        }
                    }
                }
            }
        }
        .padding()
        .navigationTitle("History")
        .onAppear {
            model.loadHistory()
        }
    }
}
