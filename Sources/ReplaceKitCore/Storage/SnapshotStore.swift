import Foundation

public enum SnapshotReason: String, Codable, Sendable {
    case manual
    case beforeEdit
    case dailyOpen

    public var displayName: String {
        switch self {
        case .manual:
            "Manual backup"
        case .beforeEdit:
            "Before edit"
        case .dailyOpen:
            "Daily app-open backup"
        }
    }
}

public struct SnapshotMetadata: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let schemaVersion: Int
    public let tagsByShortcut: [String: Set<String>]
    public let reason: SnapshotReason

    public init(
        timestamp: Date,
        schemaVersion: Int,
        tagsByShortcut: [String: Set<String>],
        reason: SnapshotReason
    ) {
        self.timestamp = timestamp
        self.schemaVersion = schemaVersion
        self.tagsByShortcut = tagsByShortcut
        self.reason = reason
    }
}

public struct Snapshot: Identifiable, Equatable, Sendable {
    public let plistURL: URL
    public let metadataURL: URL
    public let metadata: SnapshotMetadata

    public var id: URL { metadataURL }

    public init(plistURL: URL, metadataURL: URL, metadata: SnapshotMetadata) {
        self.plistURL = plistURL
        self.metadataURL = metadataURL
        self.metadata = metadata
    }
}

public struct SnapshotStore: Sendable {
    public let folder: URL
    public let codec: TextReplacementPlistCodec

    public init(folder: URL, codec: TextReplacementPlistCodec) {
        self.folder = folder
        self.codec = codec
    }

    public func writeSnapshot(
        replacements: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        reason: SnapshotReason,
        now: Date = .now
    ) throws -> Snapshot? {
        let plist = try codec.encode(replacements)
        let metadata = SnapshotMetadata(
            timestamp: now,
            schemaVersion: configuration.schemaVersion,
            tagsByShortcut: configuration.tagsByShortcut,
            reason: reason
        )

        if let latest = try list().first,
           try Data(contentsOf: latest.plistURL) == plist,
           latest.metadata.tagsByShortcut == metadata.tagsByShortcut {
            return nil
        }

        let snapshotsFolder = folder.appending(path: "snapshots")
        try FileManager.default.createDirectory(at: snapshotsFolder, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stem = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        let plistURL = snapshotsFolder.appending(path: "\(stem).plist")
        let metadataURL = snapshotsFolder.appending(path: "\(stem).metadata.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try plist.write(to: plistURL, options: .atomic)
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
        return Snapshot(plistURL: plistURL, metadataURL: metadataURL, metadata: metadata)
    }

    public func list() throws -> [Snapshot] {
        let snapshotsFolder = folder.appending(path: "snapshots")
        guard FileManager.default.fileExists(atPath: snapshotsFolder.path()) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try FileManager.default
            .contentsOfDirectory(at: snapshotsFolder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".metadata.json") }
            .map { metadataURL in
                let metadata = try decoder.decode(SnapshotMetadata.self, from: Data(contentsOf: metadataURL))
                let stem = metadataURL.lastPathComponent.replacingOccurrences(of: ".metadata.json", with: "")
                return Snapshot(
                    plistURL: snapshotsFolder.appending(path: "\(stem).plist"),
                    metadataURL: metadataURL,
                    metadata: metadata
                )
            }
            .sorted { $0.metadata.timestamp > $1.metadata.timestamp }
    }
}
