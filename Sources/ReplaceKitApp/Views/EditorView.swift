import ReplaceKitCore
import SwiftUI

struct EditorView: View {
    @Bindable var model: AppModel
    @State private var isAdding = false

    var body: some View {
        VStack(spacing: 0) {
            if model.backupFolder == nil {
                SetupBanner(model: model)
            }

            HSplitView {
                replacementTable
                    .frame(minWidth: 500)

                if let replacement = model.selectedReplacement {
                    ReplacementInspector(model: model, replacement: replacement)
                        .id("\(replacement.shortcut)|\(replacement.phrase)")
                        .frame(minWidth: 280)
                } else {
                    ContentUnavailableView(
                        "Select a replacement",
                        systemImage: "text.cursor",
                        description: Text("Choose one row to edit its shortcut, phrase, and tags.")
                    )
                    .frame(minWidth: 280)
                }
            }
        }
        .navigationTitle("Text Replacements")
        .searchable(text: $model.searchText, prompt: "Shortcut, phrase, or tag")
        .toolbar {
            Button {
                isAdding = true
            } label: {
                Label("Add", systemImage: "plus")
            }

            Button {
                model.importPlist()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }

            Button {
                model.backUpNow()
            } label: {
                Label("Back Up Now", systemImage: "externaldrive.badge.plus")
            }

            Button {
                Task { await model.deleteSelected() }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(model.selectedShortcuts.isEmpty)
        }
        .sheet(isPresented: $isAdding) {
            AddReplacementSheet(model: model, isPresented: $isAdding)
        }
    }

    private var replacementTable: some View {
        Table(model.filteredReplacements, selection: $model.selectedShortcuts) {
            TableColumn("Shortcut", value: \.shortcut)
                .width(min: 120, ideal: 160)
            TableColumn("Phrase") { replacement in
                Text(replacement.phrase)
                    .lineLimit(1)
            }
            TableColumn("Tags") { replacement in
                Text((model.configuration.tagsByShortcut[replacement.shortcut] ?? []).sorted().joined(separator: ", "))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 180)
        }
    }
}

private struct SetupBanner: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack {
            Image(systemName: "externaldrive.badge.exclamationmark")
            Text("Choose a backup folder before protected edits.")
            Spacer()
            Button("Choose Folder") {
                model.chooseBackupFolder()
            }
        }
        .padding(10)
        .background(.orange.opacity(0.15))
    }
}

private struct AddReplacementSheet: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    @State private var shortcut = ""
    @State private var phrase = ""
    @State private var tags = ""

    var body: some View {
        Form {
            TextField("Shortcut", text: $shortcut)
            TextField("Phrase", text: $phrase, axis: .vertical)
                .lineLimit(3...8)
            TextField("Tags", text: $tags, prompt: Text("work, personal"))
        }
        .padding()
        .frame(width: 460)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isPresented = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let nextTags = Set(tags.split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.filter { !$0.isEmpty })
                    isPresented = false
                    Task {
                        await model.add(shortcut: shortcut, phrase: phrase, tags: nextTags)
                    }
                }
                .disabled(shortcut.isEmpty)
            }
        }
    }
}

private struct ReplacementInspector: View {
    @Bindable var model: AppModel
    let replacement: TextReplacement
    @State private var shortcut: String
    @State private var phrase: String
    @State private var tags: String

    init(model: AppModel, replacement: TextReplacement) {
        self.model = model
        self.replacement = replacement
        _shortcut = State(initialValue: replacement.shortcut)
        _phrase = State(initialValue: replacement.phrase)
        _tags = State(initialValue: (
            model.configuration.tagsByShortcut[replacement.shortcut] ?? []
        ).sorted().joined(separator: ", "))
    }

    var body: some View {
        Form {
            TextField("Shortcut", text: $shortcut)
            TextField("Phrase", text: $phrase, axis: .vertical)
                .lineLimit(6...14)
            TextField("Tags", text: $tags, prompt: Text("work, personal"))
            HStack {
                Button("Save") {
                    let nextTags = Set(tags.split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.filter { !$0.isEmpty })
                    Task {
                        await model.update(
                            originalShortcut: replacement.shortcut,
                            shortcut: shortcut,
                            phrase: phrase,
                            tags: nextTags
                        )
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Delete", role: .destructive) {
                    Task { await model.deleteSelected() }
                }
            }
        }
        .padding()
    }
}
