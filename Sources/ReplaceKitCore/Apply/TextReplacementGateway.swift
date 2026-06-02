public protocol TextReplacementReading: Sendable {
    func fetchAll() throws -> [TextReplacement]
}

public protocol TextReplacementWriting: Sendable {
    func add(_ replacement: TextReplacement) async throws
    func update(originalShortcut: String, replacement: TextReplacement) async throws
    func delete(shortcut: String) async throws
}
