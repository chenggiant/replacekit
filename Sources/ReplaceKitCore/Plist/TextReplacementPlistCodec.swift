import Foundation

public struct TextReplacementPlistCodec: Sendable {
    private struct Record: Codable {
        let shortcut: String
        let phrase: String
        let isEnabled: Int

        enum CodingKeys: String, CodingKey {
            case shortcut = "replace"
            case phrase = "with"
            case isEnabled = "on"
        }
    }

    public init() {}

    public func encode(_ replacements: [TextReplacement]) throws -> Data {
        try TextReplacement.validateUnique(replacements)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(replacements.map {
            Record(shortcut: $0.shortcut, phrase: $0.phrase, isEnabled: $0.isEnabled ? 1 : 0)
        })
    }

    public func decode(_ data: Data) throws -> [TextReplacement] {
        let records = try PropertyListDecoder().decode([Record].self, from: data)
        let replacements = records.map {
            TextReplacement(shortcut: $0.shortcut, phrase: $0.phrase, isEnabled: $0.isEnabled != 0)
        }
        try TextReplacement.validateUnique(replacements)
        return replacements
    }
}
