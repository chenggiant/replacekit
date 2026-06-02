import Foundation
import ReplaceKitCore

public enum GlobalDefaultsReaderError: Error, Equatable {
    case preferenceUnavailable
    case malformedRecord
}

public struct GlobalDefaultsTextReplacementReader: TextReplacementReading, @unchecked Sendable {
    public typealias LoadRecords = () -> [[String: Any]]?

    private let loadRecords: LoadRecords

    public init(loadRecords: @escaping LoadRecords = {
        UserDefaults.standard
            .persistentDomain(forName: UserDefaults.globalDomain)?["NSUserDictionaryReplacementItems"]
            as? [[String: Any]]
    }) {
        self.loadRecords = loadRecords
    }

    public func fetchAll() throws -> [TextReplacement] {
        guard let records = loadRecords() else {
            throw GlobalDefaultsReaderError.preferenceUnavailable
        }
        let replacements = try records.map { record -> TextReplacement in
            guard let shortcut = record["replace"] as? String, let phrase = record["with"] else {
                throw GlobalDefaultsReaderError.malformedRecord
            }
            return TextReplacement(
                shortcut: shortcut,
                phrase: String(describing: phrase),
                isEnabled: (record["on"] as? NSNumber)?.boolValue ?? true
            )
        }
        try TextReplacement.validateUnique(replacements)
        return replacements.sorted { $0.shortcut < $1.shortcut }
    }
}
