import Foundation

public struct BackupFolderPreference: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "backupFolderPath"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> URL? {
        defaults.string(forKey: key).map(URL.init(fileURLWithPath:))
    }

    public func save(_ folder: URL?) {
        defaults.set(folder?.path(), forKey: key)
    }
}
