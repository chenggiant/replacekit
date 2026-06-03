import Foundation

public struct RoutineUpdatePlan: Sendable {
    public let mutation: ReplacementMutation?
    public let proposed: [TextReplacement]
    public let nextConfiguration: ReplaceKitConfiguration

    public var changesAppleRecords: Bool {
        mutation != nil
    }

    public init(
        mutation: ReplacementMutation?,
        proposed: [TextReplacement],
        nextConfiguration: ReplaceKitConfiguration
    ) {
        self.mutation = mutation
        self.proposed = proposed
        self.nextConfiguration = nextConfiguration
    }
}

public enum RoutineEditPlanner {
    public static func planUpdate(
        current: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        originalShortcut: String,
        shortcut: String,
        phrase: String,
        tags: Set<String>
    ) throws -> RoutineUpdatePlan {
        guard !shortcut.isEmpty else {
            throw ReplacementValidationError.emptyShortcut
        }
        guard !current.contains(where: {
            $0.shortcut == shortcut && $0.shortcut != originalShortcut
        }) else {
            throw ReplacementValidationError.duplicateShortcut(shortcut)
        }

        var nextConfiguration = configuration.renamingShortcut(
            from: originalShortcut,
            to: shortcut
        )
        if tags.isEmpty {
            nextConfiguration.tagsByShortcut.removeValue(forKey: shortcut)
        } else {
            nextConfiguration.tagsByShortcut[shortcut] = tags
        }

        let replacement = TextReplacement(shortcut: shortcut, phrase: phrase)
        let proposed = (current.filter { $0.shortcut != originalShortcut } + [replacement])
            .sorted { $0.shortcut < $1.shortcut }
        try TextReplacement.validateUnique(proposed)

        let existing = current.first { $0.shortcut == originalShortcut }
        let mutation: ReplacementMutation?
        if existing == replacement {
            mutation = nil
        } else {
            mutation = .update(originalShortcut: originalShortcut, replacement: replacement)
        }

        return RoutineUpdatePlan(
            mutation: mutation,
            proposed: proposed,
            nextConfiguration: nextConfiguration
        )
    }
}
