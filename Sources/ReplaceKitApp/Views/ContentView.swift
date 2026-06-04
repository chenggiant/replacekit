import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.sidebarSelection) {
                Text("All Replacements")
                    .tag(SidebarSelection.all)

                Section("Tags") {
                    ForEach(model.allTags, id: \.self) { tag in
                        Text(tag)
                            .tag(SidebarSelection.tag(tag))
                    }
                }

                Section {
                    Label("History", systemImage: "clock.arrow.circlepath")
                        .tag(SidebarSelection.history)
                    Label("Settings", systemImage: "gear")
                        .tag(SidebarSelection.settings)
                }
            }
            .navigationTitle("ReplaceKit")
        } detail: {
            switch model.sidebarSelection {
            case .history?:
                HistoryView(model: model)
            case .settings?:
                SettingsView(model: model)
            case .all?, .tag?, nil:
                EditorView(model: model)
            }
        }
        .sheet(isPresented: $model.isShowingDiffPreview) {
            DiffPreviewView(model: model)
        }
        .alert("Could Not Complete Action", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
