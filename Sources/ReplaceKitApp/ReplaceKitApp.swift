import SwiftUI

@main
struct ReplaceKitApp: App {
    @State private var model = AppModel.runtime()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1120, minHeight: 680)
                .task {
                    model.refresh()
                    model.createDailySnapshotIfEnabled()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Replacement") {
                    model.isShowingAddReplacement = true
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.isBusy)
            }

            CommandMenu("Replacement") {
                Button("Import Text Replacements...") {
                    model.importPlist()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.isBusy)

                Button("Back Up Now") {
                    model.backUpNow()
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(model.isBusy)

                Divider()

                Button(model.deleteSelectionTitle) {
                    Task { await model.deleteSelected() }
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.visibleSelectedShortcuts.isEmpty || model.isBusy)
            }
        }
    }
}
