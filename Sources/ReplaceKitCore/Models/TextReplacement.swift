import Foundation

public struct TextReplacement: Codable, Hashable, Identifiable, Sendable {
    public let shortcut: String
    public let phrase: String
    public let isEnabled: Bool

    public var id: String { shortcut }

    public init(shortcut: String, phrase: String, isEnabled: Bool = true) {
        self.shortcut = shortcut
        self.phrase = phrase
        self.isEnabled = isEnabled
    }

    public static func validateUnique(_ replacements: [TextReplacement]) throws {
        var seen = Set<String>()
        for replacement in replacements {
            guard !replacement.shortcut.isEmpty else {
                throw ReplacementValidationError.emptyShortcut
            }
            guard seen.insert(replacement.shortcut).inserted else {
                throw ReplacementValidationError.duplicateShortcut(replacement.shortcut)
            }
        }
    }
}

public enum ReplacementValidationError: Error, Equatable {
    case emptyShortcut
    case duplicateShortcut(String)
}
