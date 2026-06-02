import AppKit
import Foundation
import Observation
import ReplaceKitCore
import ReplaceKitMac
import UniformTypeIdentifiers

enum SidebarSelection: Hashable {
    case all
    case tag(String)
    case history
    case settings
}

struct PendingRoutineEdit {
    let mutation: ReplacementMutation
    let proposed: [TextReplacement]
    let nextConfiguration: ReplaceKitConfiguration
}

struct PendingBulkEdit {
    let proposed: [TextReplacement]
    var previewBasis: [TextReplacement]
    let nextConfiguration: ReplaceKitConfiguration
}

enum PendingProtectedApply {
    case routine(PendingRoutineEdit)
    case bulk(PendingBulkEdit)
}

enum AppModelError: Error {
    case backupFolderUnavailable
}

private struct MissingSnapshotWriter: SnapshotWriting {
    func write(
        replacements: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        reason: SnapshotReason
    ) throws {
        throw AppModelError.backupFolderUnavailable
    }
}

@MainActor
@Observable
final class AppModel {
    var replacements: [TextReplacement] = []
    var configuration = ReplaceKitConfiguration()
    var sidebarSelection: SidebarSelection? = .all
    var selectedShortcuts = Set<String>()
    var searchText = ""
    var backupFolder: URL?
    var snapshots: [Snapshot] = []
    var pendingDiff: ReplacementDiff?
    var pendingBulkEdit: PendingBulkEdit?
    var isShowingDiffPreview = false
    var pendingProtectedApply: PendingProtectedApply?
    var fallbackPlistURL: URL?
    var errorMessage: String?
    var isBusy = false

    private let reader: any TextReplacementReading
    private let writer: any TextReplacementWriting
    private let backupFolderPreference: BackupFolderPreference
    private let manualImportService: ManualImportService

    init(
        reader: any TextReplacementReading,
        writer: any TextReplacementWriting,
        backupFolderPreference: BackupFolderPreference = .init(),
        manualImportService: ManualImportService = .init()
    ) {
        self.reader = reader
        self.writer = writer
        self.backupFolderPreference = backupFolderPreference
        self.manualImportService = manualImportService
        backupFolder = backupFolderPreference.load()
    }

    static func live() -> AppModel {
        AppModel(
            reader: GlobalDefaultsTextReplacementReader(),
            writer: SystemSettingsTextReplacementWriter()
        )
    }

    var allTags: [String] {
        Array(Set(configuration.tagsByShortcut.values.flatMap { $0 })).sorted()
    }

    var filteredReplacements: [TextReplacement] {
        replacements.filter { replacement in
            let tags = configuration.tagsByShortcut[replacement.shortcut] ?? []
            let matchesTag: Bool
            if case let .tag(tag)? = sidebarSelection {
                matchesTag = tags.contains(tag)
            } else {
                matchesTag = true
            }
            guard matchesTag else { return false }
            guard !searchText.isEmpty else { return true }
            return replacement.shortcut.localizedCaseInsensitiveContains(searchText) ||
                replacement.phrase.localizedCaseInsensitiveContains(searchText) ||
                tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var selectedReplacement: TextReplacement? {
        guard selectedShortcuts.count == 1, let shortcut = selectedShortcuts.first else {
            return nil
        }
        return replacements.first { $0.shortcut == shortcut }
    }

    var accessibilityTrusted: Bool {
        AccessibilityTrust().isTrusted(prompt: false)
    }

    func refresh() {
        do {
            replacements = try reader.fetchAll()
            if let backupFolder {
                configuration = try ConfigurationStore(folder: backupFolder).load()
                snapshots = try SnapshotStore(folder: backupFolder, codec: .init()).list()
            }
        } catch {
            errorMessage = "Could not load Text Replacements: \(error)"
        }
    }

    func chooseBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        backupFolder = folder
        backupFolderPreference.save(folder)
        do {
            configuration = try ConfigurationStore(folder: folder).load()
            snapshots = try SnapshotStore(folder: folder, codec: .init()).list()
        } catch {
            errorMessage = "Could not open backup folder: \(error)"
        }
    }

    func add(shortcut: String, phrase: String, tags: Set<String>) async {
        guard !shortcut.isEmpty else {
            errorMessage = "Shortcut cannot be empty."
            return
        }
        guard !replacements.contains(where: { $0.shortcut == shortcut }) else {
            errorMessage = "Shortcut \(shortcut) already exists."
            return
        }
        var nextConfiguration = configuration
        nextConfiguration.tagsByShortcut[shortcut] = tags
        let proposed = (replacements + [.init(shortcut: shortcut, phrase: phrase)])
            .sorted { $0.shortcut < $1.shortcut }
        await apply(.init(
            mutation: .add(.init(shortcut: shortcut, phrase: phrase)),
            proposed: proposed,
            nextConfiguration: nextConfiguration
        ))
    }

    func update(
        originalShortcut: String,
        shortcut: String,
        phrase: String,
        tags: Set<String>
    ) async {
        guard !shortcut.isEmpty else {
            errorMessage = "Shortcut cannot be empty."
            return
        }
        guard !replacements.contains(where: {
            $0.shortcut == shortcut && $0.shortcut != originalShortcut
        }) else {
            errorMessage = "Shortcut \(shortcut) already exists."
            return
        }
        var nextConfiguration = configuration.renamingShortcut(from: originalShortcut, to: shortcut)
        nextConfiguration.tagsByShortcut[shortcut] = tags
        let replacement = TextReplacement(shortcut: shortcut, phrase: phrase)
        let proposed = replacements
            .filter { $0.shortcut != originalShortcut } + [replacement]
        await apply(.init(
            mutation: .update(originalShortcut: originalShortcut, replacement: replacement),
            proposed: proposed.sorted { $0.shortcut < $1.shortcut },
            nextConfiguration: nextConfiguration
        ))
    }

    func deleteSelected() async {
        guard !selectedShortcuts.isEmpty else { return }
        if selectedShortcuts.count > 1 {
            previewDelete(shortcuts: selectedShortcuts)
            return
        }
        guard let shortcut = selectedShortcuts.first else { return }
        var nextConfiguration = configuration
        nextConfiguration.tagsByShortcut.removeValue(forKey: shortcut)
        await apply(.init(
            mutation: .delete(shortcut: shortcut),
            proposed: replacements.filter { $0.shortcut != shortcut },
            nextConfiguration: nextConfiguration
        ))
    }

    func applyPendingWithoutSnapshot() async {
        guard let pendingProtectedApply else { return }
        switch pendingProtectedApply {
        case let .routine(edit):
            await apply(edit, protection: .unprotectedOnce)
        case let .bulk(edit):
            await applyBulk(edit, protection: .unprotectedOnce)
        }
    }

    func backUpNow() {
        guard let backupFolder else {
            errorMessage = "Choose a backup folder first."
            return
        }
        do {
            _ = try SnapshotStore(folder: backupFolder, codec: .init()).writeSnapshot(
                replacements: try reader.fetchAll(),
                configuration: configuration,
                reason: .manual
            )
            loadHistory()
        } catch {
            errorMessage = "Backup failed: \(error)"
        }
    }

    func createDailySnapshotIfEnabled() {
        guard
            configuration.createDailySnapshotOnOpen,
            let backupFolder
        else {
            return
        }
        do {
            let store = SnapshotStore(folder: backupFolder, codec: .init())
            let calendar = Calendar.current
            guard try !store.list().contains(where: {
                $0.metadata.reason == .dailyOpen &&
                    calendar.isDateInToday($0.metadata.timestamp)
            }) else {
                return
            }
            _ = try store.writeSnapshot(
                replacements: try reader.fetchAll(),
                configuration: configuration,
                reason: .dailyOpen
            )
            loadHistory()
        } catch {
            errorMessage = "Daily backup failed: \(error)"
        }
    }

    func loadHistory() {
        guard let backupFolder else {
            snapshots = []
            return
        }
        do {
            snapshots = try SnapshotStore(folder: backupFolder, codec: .init()).list()
        } catch {
            errorMessage = "Could not load history: \(error)"
        }
    }

    func importPlist() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let proposed = try TextReplacementPlistCodec().decode(Data(contentsOf: url))
            prepareBulk(proposed: proposed, nextConfiguration: configuration)
        } catch {
            errorMessage = "Import failed: \(error)"
        }
    }

    func previewRestore(_ snapshot: Snapshot) {
        do {
            let proposed = try TextReplacementPlistCodec().decode(Data(contentsOf: snapshot.plistURL))
            var nextConfiguration = configuration
            nextConfiguration.tagsByShortcut = snapshot.metadata.tagsByShortcut
            prepareBulk(proposed: proposed, nextConfiguration: nextConfiguration)
        } catch {
            errorMessage = "Could not read snapshot: \(error)"
        }
    }

    func previewDelete(shortcuts: Set<String>) {
        var nextConfiguration = configuration
        for shortcut in shortcuts {
            nextConfiguration.tagsByShortcut.removeValue(forKey: shortcut)
        }
        prepareBulk(
            proposed: replacements.filter { !shortcuts.contains($0.shortcut) },
            nextConfiguration: nextConfiguration
        )
    }

    func confirmPendingBulkApply() async {
        guard let pendingBulkEdit else { return }
        await applyBulk(pendingBulkEdit)
    }

    func cancelPendingBulkApply() {
        pendingBulkEdit = nil
        pendingDiff = nil
        isShowingDiffPreview = false
    }

    func saveConfiguration() {
        guard let backupFolder else { return }
        do {
            try ConfigurationStore(folder: backupFolder).save(configuration)
        } catch {
            errorMessage = "Could not save settings: \(error)"
        }
    }

    func requestAccessibilityPermission() {
        _ = AccessibilityTrust().isTrusted(prompt: true)
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!)
    }

    func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(
            string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        )!)
    }

    func exportFallbackPlist(_ proposed: [TextReplacement]? = nil) {
        do {
            let folder = backupFolder ?? FileManager.default.temporaryDirectory
            let values = try proposed ?? reader.fetchAll()
            fallbackPlistURL = try manualImportService.export(values, to: folder)
        } catch {
            errorMessage = "Could not export fallback plist: \(error)"
        }
    }

    func revealFallbackPlist() {
        guard let fallbackPlistURL else { return }
        manualImportService.revealInFinder(fallbackPlistURL)
    }

    private func apply(
        _ edit: PendingRoutineEdit,
        protection: SnapshotProtection = .required
    ) async {
        isBusy = true
        defer { isBusy = false }
        let coordinator = ApplyCoordinator(
            reader: reader,
            writer: writer,
            snapshots: snapshotWriter()
        )
        do {
            replacements = try await coordinator.apply(
                edit.mutation,
                configuration: configuration,
                protection: protection
            ).observed
            configuration = edit.nextConfiguration
            selectedShortcuts = []
            try saveConfigurationIfPossible()
            pendingProtectedApply = nil
            loadHistory()
        } catch ApplyCoordinatorError.snapshotUnavailable {
            pendingProtectedApply = .routine(edit)
            errorMessage = "Choose a writable backup folder or apply this edit once without a snapshot."
        } catch ApplyCoordinatorError.partialResult(let observed, let message) {
            replacements = observed
            errorMessage = "System Settings applied only part of the change: \(message)"
            exportFallbackPlist(edit.proposed)
        } catch {
            errorMessage = "Could not apply change: \(error)"
            exportFallbackPlist(edit.proposed)
        }
    }

    private func prepareBulk(
        proposed: [TextReplacement],
        nextConfiguration: ReplaceKitConfiguration
    ) {
        let edit = PendingBulkEdit(
            proposed: proposed.sorted { $0.shortcut < $1.shortcut },
            previewBasis: replacements,
            nextConfiguration: nextConfiguration
        )
        pendingBulkEdit = edit
        pendingDiff = .compare(current: replacements, proposed: edit.proposed)
        isShowingDiffPreview = true
    }

    private func applyBulk(
        _ edit: PendingBulkEdit,
        protection: SnapshotProtection = .required
    ) async {
        isBusy = true
        defer { isBusy = false }
        let coordinator = ApplyCoordinator(
            reader: reader,
            writer: writer,
            snapshots: snapshotWriter()
        )
        do {
            replacements = try await coordinator.apply(
                proposed: edit.proposed,
                previewBasis: edit.previewBasis,
                configuration: configuration,
                protection: protection
            ).observed
            configuration = edit.nextConfiguration
            try saveConfigurationIfPossible()
            pendingProtectedApply = nil
            cancelPendingBulkApply()
            selectedShortcuts = []
            loadHistory()
        } catch ApplyCoordinatorError.changedBasis(let diff) {
            var refreshed = edit
            refreshed.previewBasis = (try? reader.fetchAll()) ?? replacements
            pendingBulkEdit = refreshed
            pendingDiff = diff
            isShowingDiffPreview = true
            errorMessage = "Text Replacements changed outside ReplaceKit. Review the updated diff."
        } catch ApplyCoordinatorError.snapshotUnavailable {
            pendingProtectedApply = .bulk(edit)
            errorMessage = "Choose a writable backup folder or apply these changes once without a snapshot."
        } catch ApplyCoordinatorError.partialResult(let observed, let message) {
            replacements = observed
            errorMessage = "System Settings applied only part of the bulk change: \(message)"
            exportFallbackPlist(edit.proposed)
        } catch {
            errorMessage = "Could not apply bulk change: \(error)"
            exportFallbackPlist(edit.proposed)
        }
    }

    private func snapshotWriter() -> any SnapshotWriting {
        guard let backupFolder else {
            return MissingSnapshotWriter()
        }
        return SnapshotStore(folder: backupFolder, codec: .init())
    }

    private func saveConfigurationIfPossible() throws {
        guard let backupFolder else { return }
        try ConfigurationStore(folder: backupFolder).save(configuration)
    }
}
