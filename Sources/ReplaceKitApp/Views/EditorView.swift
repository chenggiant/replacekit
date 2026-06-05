import ReplaceKitCore
import SwiftUI

struct EditorView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.backupFolder == nil {
                SetupBanner(model: model)
            }

            HSplitView {
                replacementTable
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

                if let replacement = model.selectedReplacement {
                    ReplacementInspector(model: model, replacement: replacement)
                        .id("\(replacement.shortcut)|\(replacement.phrase)")
                        .frame(minWidth: 400, idealWidth: 440, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "Select a replacement",
                        systemImage: "text.badge.checkmark",
                        description: Text("Choose one row to edit its shortcut, phrase, and tags.")
                    )
                    .frame(minWidth: 400, idealWidth: 440, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Text Replacements")
        .searchable(text: $model.searchText, prompt: "Shortcut, phrase, or tag")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.isShowingAddReplacement = true
                } label: {
                    Label("Add Replacement", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .help("Add a text replacement")
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.isBusy)
            }

            ToolbarItemGroup(placement: .secondaryAction) {
                Button {
                    model.importPlist()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
                .help("Import a Text Replacements plist")
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.isBusy)

                Button {
                    model.backUpNow()
                } label: {
                    Label("Back Up Now", systemImage: "externaldrive.badge.plus")
                        .labelStyle(.titleAndIcon)
                }
                .help("Create a backup snapshot")
                .keyboardShortcut("b", modifiers: .command)
                .disabled(model.isBusy)
            }

            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    Task { await model.deleteSelected() }
                } label: {
                    Label(model.deleteSelectionTitle, systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
                .help("Delete the selected replacements")
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.visibleSelectedShortcuts.isEmpty || model.isBusy)
            }
        }
        .sheet(isPresented: $model.isShowingAddReplacement) {
            AddReplacementSheet(model: model, isPresented: $model.isShowingAddReplacement)
        }
        .onChange(of: model.searchText) {
            model.pruneSelectionToVisibleReplacements()
        }
        .onChange(of: model.sidebarSelection) {
            model.pruneSelectionToVisibleReplacements()
        }
    }

    private var replacementTable: some View {
        ZStack {
            Table(model.filteredReplacements, selection: $model.selectedShortcuts) {
                TableColumn("Shortcut") { replacement in
                    Text(replacement.shortcut)
                        .font(.body.monospaced())
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 160)
                TableColumn("Phrase") { replacement in
                    Text(replacement.phrase)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                TableColumn("ReplaceKit Tags") { replacement in
                    TagSummary(tags: (
                        model.configuration.tagsByShortcut[replacement.shortcut] ?? []
                    ).sorted())
                }
                .width(min: 140, ideal: 200)
            }

            if model.filteredReplacements.isEmpty {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: model.searchText.isEmpty ? "text.badge.plus" : "magnifyingglass",
                    description: Text(emptyStateDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
                .allowsHitTesting(false)
            }
        }
    }

    private var emptyStateTitle: String {
        if !model.searchText.isEmpty {
            return "No replacements match \"\(model.searchText)\""
        }
        if case .tag? = model.sidebarSelection {
            return "No replacements with this tag"
        }
        return "No text replacements"
    }

    private var emptyStateDescription: String {
        if !model.searchText.isEmpty {
            return "Try a different shortcut, phrase, or tag."
        }
        if case .tag? = model.sidebarSelection {
            return "Choose another tag or add this tag to a replacement."
        }
        return "Add your first replacement to Apple's Text Replacements."
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
        VStack(alignment: .leading, spacing: 16) {
            Text("New Replacement")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Section("Replacement") {
                    TextField("Shortcut", text: $shortcut)
                    TextField("Phrase", text: $phrase, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("ReplaceKit Tags") {
                    TextField("Tags", text: $tags, prompt: Text("work, personal"))
                    Text("Tags stay in ReplaceKit and do not sync to iPhone or iPad.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .frame(width: 460)
        .disabled(model.isBusy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    let nextTags = parseTags(tags)
                    let hadShortcut = model.replacements.contains { $0.shortcut == shortcut }
                    Task {
                        await model.add(shortcut: shortcut, phrase: phrase, tags: nextTags)
                        if !hadShortcut, model.replacements.contains(where: {
                            $0.shortcut == shortcut && $0.phrase == phrase
                        }) {
                            isPresented = false
                        }
                    }
                } label: {
                    HStack {
                        if model.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(model.isBusy ? "Adding..." : addActionTitle)
                    }
                }
                .disabled(shortcut.isEmpty || model.isBusy)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var addActionTitle: String {
        switch model.configuration.writeMode {
        case .systemSettings:
            "Add to Mac & iCloud"
        case .directDefaultsExperimental:
            "Add Locally"
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Selected Replacement")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(replacement.shortcut)
                    .font(.title3.monospaced())
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    InspectorField("Shortcut") {
                        TextField("Shortcut", text: $shortcut)
                            .textFieldStyle(.roundedBorder)
                    }

                    InspectorField("Phrase") {
                        TextField("Phrase", text: $phrase, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(6...14)
                    }

                    InspectorField("ReplaceKit Tags") {
                        TextField("work, personal", text: $tags)
                            .textFieldStyle(.roundedBorder)
                        Text("Tags are ReplaceKit-only metadata. They do not sync to iPhone or iPad.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            .disabled(model.isBusy)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack {
                Button("Delete Replacement", role: .destructive) {
                    Task { await model.deleteSelected() }
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.visibleSelectedShortcuts.isEmpty || model.isBusy)

                Spacer()

                Button {
                    Task {
                        await model.update(
                            originalShortcut: replacement.shortcut,
                            shortcut: shortcut,
                            phrase: phrase,
                            tags: parsedTags
                        )
                    }
                } label: {
                    HStack {
                        if model.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(model.isBusy ? "Applying..." : saveActionTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(shortcut.isEmpty || !isDirty || model.isBusy)
            }
            .padding()
        }
    }

    private var originalTags: Set<String> {
        model.configuration.tagsByShortcut[replacement.shortcut] ?? []
    }

    private var parsedTags: Set<String> {
        parseTags(tags)
    }

    private var isDirty: Bool {
        shortcut != replacement.shortcut ||
            phrase != replacement.phrase ||
            parsedTags != originalTags
    }

    private var isTagOnlyEdit: Bool {
        shortcut == replacement.shortcut &&
            phrase == replacement.phrase &&
            parsedTags != originalTags
    }

    private var saveActionTitle: String {
        isTagOnlyEdit ? "Save Tags" : model.configuration.writeMode.saveActionTitle
    }
}

private struct TagSummary: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(2), id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if tags.count > 2 {
                Text("+\(tags.count - 2)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct InspectorField<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

private func parseTags(_ value: String) -> Set<String> {
    Set(value.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty })
}
