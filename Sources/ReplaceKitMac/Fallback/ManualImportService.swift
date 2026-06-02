import AppKit
import Foundation
import ReplaceKitCore

public struct ManualImportService: Sendable {
    private let codec = TextReplacementPlistCodec()

    public init() {}

    public func export(_ replacements: [TextReplacement], to folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "property list.plist")
        try codec.encode(replacements).write(to: url, options: .atomic)
        return url
    }

    @MainActor
    public func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
