import Foundation
import ReplaceKitCore

private enum ScreenshotDemoMode {
    case editor
    case settings

    init?(_ rawValue: String?) {
        switch rawValue {
        case "editor":
            self = .editor
        case "settings":
            self = .settings
        default:
            return nil
        }
    }
}

private final class ScreenshotTextReplacementStore: TextReplacementReading, TextReplacementWriting, @unchecked Sendable {
    private let replacements: [TextReplacement]

    init(replacements: [TextReplacement]) {
        self.replacements = replacements
    }

    func fetchAll() throws -> [TextReplacement] {
        return replacements
    }

    func add(_ replacement: TextReplacement) async throws {}

    func update(originalShortcut: String, replacement: TextReplacement) async throws {}

    func delete(shortcut: String) async throws {}
}

extension AppModel {
    static func runtime() -> AppModel {
        guard let mode = ScreenshotDemoMode(ProcessInfo.processInfo.environment["REPLACEKIT_SCREENSHOT_MODE"]) else {
            return live()
        }
        return screenshotDemo(mode: mode)
    }

    private static func screenshotDemo(mode: ScreenshotDemoMode) -> AppModel {
        let replacements = [
            TextReplacement(shortcut: ".sig", phrase: "Best regards,\nAlex"),
            TextReplacement(shortcut: "omw", phrase: "On my way!"),
            TextReplacement(shortcut: ".addr", phrase: "123 Example Street"),
            TextReplacement(shortcut: ".reply", phrase: "Thanks for the update."),
        ]
        let store = ScreenshotTextReplacementStore(replacements: replacements)
        let model = AppModel(
            reader: store,
            writer: store,
            quietSystemSettingsWriter: store,
            directDefaultsWriter: store,
            loadBackupFolderData: false,
            accessibilityTrustedOverride: true
        )
        model.replacements = replacements
        model.configuration = ReplaceKitConfiguration(
            tagsByShortcut: [
                ".sig": ["work"],
                "omw": ["personal"],
                ".addr": ["work"],
                ".reply": ["support"],
            ],
            createDailySnapshotOnOpen: true,
            writeMode: .systemSettings,
            systemSettingsApplyMode: .quiet
        )
        model.backupFolder = FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Documents/Text Replacements Backups")
        model.selectedShortcuts = [".sig"]
        model.sidebarSelection = mode == .settings ? .settings : .all
        return model
    }
}
