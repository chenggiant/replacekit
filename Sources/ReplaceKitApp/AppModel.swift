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

enum BulkEditSource {
    case plistImport(filename: String)
    case snapshotRestore(timestamp: Date)
    case delete(shortcuts: [String])

    var title: String {
        switch self {
        case .plistImport:
            "Review Import"
        case .snapshotRestore(let timestamp):
            "Restore Snapshot from \(timestamp.formatted(date: .abbreviated, time: .omitted))"
        case .delete(let shortcuts):
            shortcuts.count == 1 ? "Review Deletion" : "Review Deletion of \(shortcuts.count) Replacements"
        }
    }

    var description: String {
        switch self {
        case .plistImport(let filename):
            "Review how \(filename) will change Apple's Text Replacements before applying it."
        case .snapshotRestore:
            "Review how this snapshot will change Apple's Text Replacements before restoring it."
        case .delete(let shortcuts):
            if let shortcut = shortcuts.first, shortcuts.count == 1 {
                "Review \(shortcut) before deleting it from Apple's Text Replacements."
            } else {
                "Review the selected replacements before deleting them from Apple's Text Replacements."
            }
        }
    }

    var confirmationTitle: String {
        switch self {
        case .plistImport:
            "Apply Import"
        case .snapshotRestore:
            "Restore Snapshot"
        case .delete(let shortcuts):
            shortcuts.count == 1 ? "Delete Replacement" : "Delete \(shortcuts.count) Replacements"
        }
    }
}

struct PendingBulkEdit {
    let proposed: [TextReplacement]
    var previewBasis: [TextReplacement]
    let nextConfiguration: ReplaceKitConfiguration
    let source: BulkEditSource
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
    var isShowingAddReplacement = false
    var pendingProtectedApply: PendingProtectedApply?
    var fallbackPlistURL: URL?
    var errorMessage: String?
    var historyErrorMessage: String?
    var isBusy = false

    private let reader: any TextReplacementReading
    private let systemSettingsWriter: any TextReplacementWriting
    private let quietSystemSettingsWriter: any TextReplacementWriting
    private let directDefaultsWriter: any TextReplacementWriting
    private let backupFolderPreference: BackupFolderPreference
    private let manualImportService: ManualImportService
    private let loadBackupFolderData: Bool
    private let accessibilityTrustedOverride: Bool?

    init(
        reader: any TextReplacementReading,
        writer: any TextReplacementWriting,
        quietSystemSettingsWriter: (any TextReplacementWriting)? = nil,
        directDefaultsWriter: any TextReplacementWriting = GlobalDefaultsTextReplacementWriter(),
        backupFolderPreference: BackupFolderPreference = .init(),
        manualImportService: ManualImportService = .init(),
        loadBackupFolderData: Bool = true,
        accessibilityTrustedOverride: Bool? = nil
    ) {
        self.reader = reader
        self.systemSettingsWriter = writer
        self.quietSystemSettingsWriter = quietSystemSettingsWriter ?? writer
        self.directDefaultsWriter = directDefaultsWriter
        self.backupFolderPreference = backupFolderPreference
        self.manualImportService = manualImportService
        self.loadBackupFolderData = loadBackupFolderData
        self.accessibilityTrustedOverride = accessibilityTrustedOverride
        backupFolder = backupFolderPreference.load()
    }

    static func live() -> AppModel {
        AppModel(
            reader: GlobalDefaultsTextReplacementReader(),
            writer: SystemSettingsTextReplacementWriter(),
            quietSystemSettingsWriter: SystemSettingsTextReplacementWriter(presentationMode: .quiet)
        )
    }

    private var activeWriter: any TextReplacementWriting {
        switch configuration.writeMode {
        case .systemSettings:
            switch configuration.systemSettingsApplyMode {
            case .standard:
                systemSettingsWriter
            case .quiet:
                quietSystemSettingsWriter
            }
        case .directDefaultsExperimental:
            directDefaultsWriter
        }
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

    var visibleSelectedShortcuts: Set<String> {
        selectedShortcuts.intersection(Set(filteredReplacements.map(\.shortcut)))
    }

    var selectedReplacement: TextReplacement? {
        let visibleSelection = visibleSelectedShortcuts
        guard visibleSelection.count == 1, let shortcut = visibleSelection.first else {
            return nil
        }
        return replacements.first { $0.shortcut == shortcut }
    }

    var deleteSelectionTitle: String {
        visibleSelectedShortcuts.count <= 1 ? "Delete Replacement" : "Delete \(visibleSelectedShortcuts.count) Replacements"
    }

    func pruneSelectionToVisibleReplacements() {
        selectedShortcuts.formIntersection(Set(filteredReplacements.map(\.shortcut)))
    }

    var accessibilityTrusted: Bool {
        if let accessibilityTrustedOverride {
            return accessibilityTrustedOverride
        }
        return AccessibilityTrust().isTrusted(prompt: false)
    }

    func refresh() {
        do {
            replacements = try reader.fetchAll()
            if loadBackupFolderData, let backupFolder {
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
        do {
            let plan = try RoutineEditPlanner.planUpdate(
                current: replacements,
                configuration: configuration,
                originalShortcut: originalShortcut,
                shortcut: shortcut,
                phrase: phrase,
                tags: tags
            )
            guard let mutation = plan.mutation else {
                saveMetadataOnly(plan.nextConfiguration)
                return
            }
            await apply(.init(
                mutation: mutation,
                proposed: plan.proposed,
                nextConfiguration: plan.nextConfiguration
            ))
        } catch ReplacementValidationError.emptyShortcut {
            errorMessage = "Shortcut cannot be empty."
        } catch ReplacementValidationError.duplicateShortcut(let shortcut) {
            errorMessage = "Shortcut \(shortcut) already exists."
        } catch {
            errorMessage = "Could not prepare change: \(error)"
        }
    }

    private func saveMetadataOnly(_ nextConfiguration: ReplaceKitConfiguration) {
        guard let backupFolder else {
            errorMessage = "Choose a backup folder before saving tags."
            return
        }
        do {
            _ = try SnapshotStore(folder: backupFolder, codec: .init()).writeSnapshot(
                replacements: try reader.fetchAll(),
                configuration: configuration,
                reason: .beforeEdit
            )
            configuration = nextConfiguration
            try ConfigurationStore(folder: backupFolder).save(configuration)
            pendingProtectedApply = nil
            loadHistory()
        } catch {
            errorMessage = "Could not save tags: \(error)"
        }
    }

    func deleteSelected() async {
        let shortcuts = visibleSelectedShortcuts
        guard !shortcuts.isEmpty else { return }
        previewDelete(shortcuts: shortcuts)
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
            loadBackupFolderData,
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
        guard loadBackupFolderData else {
            historyErrorMessage = nil
            return
        }
        guard let backupFolder else {
            snapshots = []
            historyErrorMessage = nil
            return
        }
        do {
            snapshots = try SnapshotStore(folder: backupFolder, codec: .init()).list()
            historyErrorMessage = nil
        } catch {
            snapshots = []
            historyErrorMessage = "Could not load snapshots from \(backupFolder.path(percentEncoded: false)): \(error.localizedDescription)"
            errorMessage = "Could not load history: \(error.localizedDescription)"
        }
    }

    func revealBackupFolder() {
        guard let backupFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([backupFolder])
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
            prepareBulk(
                proposed: proposed,
                nextConfiguration: configuration,
                source: .plistImport(filename: url.lastPathComponent)
            )
        } catch {
            errorMessage = "Import failed: \(error)"
        }
    }

    func previewRestore(_ snapshot: Snapshot) {
        do {
            let proposed = try TextReplacementPlistCodec().decode(Data(contentsOf: snapshot.plistURL))
            var nextConfiguration = configuration
            nextConfiguration.tagsByShortcut = snapshot.metadata.tagsByShortcut
            prepareBulk(
                proposed: proposed,
                nextConfiguration: nextConfiguration,
                source: .snapshotRestore(timestamp: snapshot.metadata.timestamp)
            )
        } catch {
            errorMessage = "Could not read snapshot: \(error)"
        }
    }

    func previewDelete(shortcuts: Set<String>) {
        let sortedShortcuts = shortcuts.sorted()
        var nextConfiguration = configuration
        for shortcut in shortcuts {
            nextConfiguration.tagsByShortcut.removeValue(forKey: shortcut)
        }
        prepareBulk(
            proposed: replacements.filter { !shortcuts.contains($0.shortcut) },
            nextConfiguration: nextConfiguration,
            source: .delete(shortcuts: sortedShortcuts)
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
        guard loadBackupFolderData, let backupFolder else { return }
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
            writer: activeWriter,
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
            errorMessage = "macOS applied only part of the change. ReplaceKit refreshed the current list, created a fallback plist, and kept the pre-change snapshot when one was available. Details: \(message)"
            exportFallbackPlist(edit.proposed)
        } catch {
            errorMessage = "Could not apply change. The replacement may be unchanged. ReplaceKit created a fallback plist you can import manually. Details: \(error.localizedDescription)"
            exportFallbackPlist(edit.proposed)
        }
    }

    private func prepareBulk(
        proposed: [TextReplacement],
        nextConfiguration: ReplaceKitConfiguration,
        source: BulkEditSource
    ) {
        let edit = PendingBulkEdit(
            proposed: proposed.sorted { $0.shortcut < $1.shortcut },
            previewBasis: replacements,
            nextConfiguration: nextConfiguration,
            source: source
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
            writer: activeWriter,
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
            errorMessage = "macOS applied only part of these changes. ReplaceKit refreshed the current list, created a fallback plist, and kept the pre-change snapshot when one was available. Details: \(message)"
            exportFallbackPlist(edit.proposed)
        } catch {
            errorMessage = "Could not apply these changes. The current Text Replacements may be unchanged. ReplaceKit created a fallback plist you can import manually. Details: \(error.localizedDescription)"
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
        guard loadBackupFolderData, let backupFolder else { return }
        try ConfigurationStore(folder: backupFolder).save(configuration)
    }
}
