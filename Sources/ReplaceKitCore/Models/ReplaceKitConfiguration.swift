import Foundation

public struct ReplaceKitConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var tagsByShortcut: [String: Set<String>]
    public var createDailySnapshotOnOpen: Bool

    public init(
        schemaVersion: Int = 1,
        tagsByShortcut: [String: Set<String>] = [:],
        createDailySnapshotOnOpen: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.tagsByShortcut = tagsByShortcut
        self.createDailySnapshotOnOpen = createDailySnapshotOnOpen
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
