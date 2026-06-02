import SwiftUI

@main
struct ReplaceKitApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    model.refresh()
                    model.createDailySnapshotIfEnabled()
                }
        }
    }
}
