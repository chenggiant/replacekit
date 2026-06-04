import Foundation
import ReplaceKitCore

public enum GlobalDefaultsWriterError: Error, Equatable {
    case malformedExistingPreference
}

public struct GlobalDefaultsTextReplacementWriter: TextReplacementWriting, @unchecked Sendable {
    public typealias LoadDomain = () -> [String: Any]?
    public typealias SaveDomain = ([String: Any]) -> Void

    private static let replacementItemsKey = "NSUserDictionaryReplacementItems"

    private let loadDomain: LoadDomain
    private let saveDomain: SaveDomain

    public init(
        loadDomain: @escaping LoadDomain = {
            UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        },
        saveDomain: @escaping SaveDomain = { domain in
            UserDefaults.standard.setPersistentDomain(domain, forName: UserDefaults.globalDomain)
            UserDefaults.standard.synchronize()
        }
    ) {
        self.loadDomain = loadDomain
        self.saveDomain = saveDomain
    }

    public func add(_ replacement: TextReplacement) async throws {
        try mutate { replacements in
            replacements.append(replacement)
        }
    }

    public func update(originalShortcut: String, replacement: TextReplacement) async throws {
        try mutate { replacements in
            replacements.removeAll { $0.shortcut == originalShortcut }
            replacements.append(replacement)
        }
    }

    public func delete(shortcut: String) async throws {
        try mutate { replacements in
            replacements.removeAll { $0.shortcut == shortcut }
        }
    }

    private func mutate(_ mutation: (inout [TextReplacement]) throws -> Void) throws {
        var domain = loadDomain() ?? [:]
        var replacements = try replacements(from: domain)
        try mutation(&replacements)
        replacements.sort { $0.shortcut < $1.shortcut }
        try TextReplacement.validateUnique(replacements)
        domain[Self.replacementItemsKey] = replacements.map(record)
        saveDomain(domain)
    }

    private func replacements(from domain: [String: Any]) throws -> [TextReplacement] {
        guard let value = domain[Self.replacementItemsKey] else {
            return []
        }
        guard let records = value as? [[String: Any]] else {
            throw GlobalDefaultsWriterError.malformedExistingPreference
        }
        return try records.map { record -> TextReplacement in
            guard let shortcut = record["replace"] as? String, let phrase = record["with"] else {
                throw GlobalDefaultsWriterError.malformedExistingPreference
            }
            return TextReplacement(
                shortcut: shortcut,
                phrase: String(describing: phrase),
                isEnabled: (record["on"] as? NSNumber)?.boolValue ?? true
            )
        }
    }

    private func record(from replacement: TextReplacement) -> [String: Any] {
        [
            "on": replacement.isEnabled ? 1 : 0,
            "replace": replacement.shortcut,
            "with": replacement.phrase,
        ]
    }
}
