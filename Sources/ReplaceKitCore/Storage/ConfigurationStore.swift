import Foundation

public struct ConfigurationStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func load() throws -> ReplaceKitConfiguration {
        let url = folder.appending(path: "replacekit.json")
        guard FileManager.default.fileExists(atPath: url.path()) else {
            return .init()
        }
        return try JSONDecoder().decode(ReplaceKitConfiguration.self, from: Data(contentsOf: url))
    }

    public func save(_ configuration: ReplaceKitConfiguration) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(
            to: folder.appending(path: "replacekit.json"),
            options: .atomic
        )
    }
}
