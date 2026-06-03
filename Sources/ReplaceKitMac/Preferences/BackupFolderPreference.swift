import Foundation

public struct BackupFolderPreference: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "backupFolderPath"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> URL? {
        guard let storedPath = defaults.string(forKey: key) else { return nil }
        return URL(fileURLWithPath: storedPath.removingPercentEncoding ?? storedPath)
    }

    public func save(_ folder: URL?) {
        defaults.set(folder?.path(percentEncoded: false), forKey: key)
    }
}
