import Foundation

public enum ReplacementWriteMode: String, Codable, CaseIterable, Equatable, Sendable {
    case systemSettings
    case directDefaultsExperimental

    public var displayName: String {
        switch self {
        case .systemSettings:
            "System Settings + iCloud (Recommended)"
        case .directDefaultsExperimental:
            "Local Only (Experimental)"
        }
    }

    public var saveActionTitle: String {
        switch self {
        case .systemSettings:
            "Save to Mac & iCloud"
        case .directDefaultsExperimental:
            "Save Locally"
        }
    }
}

public enum SystemSettingsApplyMode: String, Codable, CaseIterable, Equatable, Sendable {
    case standard
    case quiet
}

public struct ReplaceKitConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var tagsByShortcut: [String: Set<String>]
    public var createDailySnapshotOnOpen: Bool
    public var writeMode: ReplacementWriteMode
    public var systemSettingsApplyMode: SystemSettingsApplyMode

    public init(
        schemaVersion: Int = 1,
        tagsByShortcut: [String: Set<String>] = [:],
        createDailySnapshotOnOpen: Bool = false,
        writeMode: ReplacementWriteMode = .systemSettings,
        systemSettingsApplyMode: SystemSettingsApplyMode = .quiet
    ) {
        self.schemaVersion = schemaVersion
        self.tagsByShortcut = tagsByShortcut
        self.createDailySnapshotOnOpen = createDailySnapshotOnOpen
        self.writeMode = writeMode
        self.systemSettingsApplyMode = systemSettingsApplyMode
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tagsByShortcut
        case createDailySnapshotOnOpen
        case writeMode
        case systemSettingsApplyMode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        tagsByShortcut = try container.decodeIfPresent([String: Set<String>].self, forKey: .tagsByShortcut) ?? [:]
        createDailySnapshotOnOpen = try container.decodeIfPresent(
            Bool.self,
            forKey: .createDailySnapshotOnOpen
        ) ?? false
        writeMode = try container.decodeIfPresent(ReplacementWriteMode.self, forKey: .writeMode) ?? .systemSettings
        systemSettingsApplyMode = try container.decodeIfPresent(
            SystemSettingsApplyMode.self,
            forKey: .systemSettingsApplyMode
        ) ?? .quiet
    }

    public func renamingShortcut(from oldShortcut: String, to newShortcut: String) -> Self {
        guard oldShortcut != newShortcut else { return self }
        var copy = self
        if let tags = copy.tagsByShortcut.removeValue(forKey: oldShortcut) {
            copy.tagsByShortcut[newShortcut] = tags
        }
        return copy
    }
}
