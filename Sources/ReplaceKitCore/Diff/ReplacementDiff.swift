import Foundation

public struct EditedReplacement: Equatable, Sendable {
    public let before: TextReplacement
    public let after: TextReplacement

    public init(before: TextReplacement, after: TextReplacement) {
        self.before = before
        self.after = after
    }
}

public struct ReplacementDiff: Equatable, Sendable {
    public let added: [TextReplacement]
    public let edited: [EditedReplacement]
    public let deleted: [TextReplacement]

    public init(
        added: [TextReplacement],
        edited: [EditedReplacement],
        deleted: [TextReplacement]
    ) {
        self.added = added
        self.edited = edited
        self.deleted = deleted
    }

    public static func compare(current: [TextReplacement], proposed: [TextReplacement]) -> Self {
        let old = Dictionary(uniqueKeysWithValues: current.map { ($0.shortcut, $0) })
        let new = Dictionary(uniqueKeysWithValues: proposed.map { ($0.shortcut, $0) })

        let added = Set(new.keys)
            .subtracting(old.keys)
            .compactMap { new[$0] }
            .sorted { $0.shortcut < $1.shortcut }
        let deleted = Set(old.keys)
            .subtracting(new.keys)
            .compactMap { old[$0] }
            .sorted { $0.shortcut < $1.shortcut }
        let edited = Set(old.keys)
            .intersection(new.keys)
            .compactMap { key -> EditedReplacement? in
                guard let before = old[key], let after = new[key], before != after else {
                    return nil
                }
                return EditedReplacement(before: before, after: after)
            }
            .sorted { $0.after.shortcut < $1.after.shortcut }

        return .init(added: added, edited: edited, deleted: deleted)
    }

    public static func basisChanged(preview: [TextReplacement], observed: [TextReplacement]) -> Bool {
        Set(preview) != Set(observed)
    }
}
