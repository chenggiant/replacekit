# ReplaceKit V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS utility that reads Apple's current Text Replacements, manages tags and versioned plist snapshots, previews bulk changes, and applies confirmed edits through Apple's System Settings UI.

**Architecture:** Use a Swift Package with three targets: `ReplaceKitCore` for portable models, plist, tags, history, diffs, and orchestration; `ReplaceKitMac` for read-only macOS preferences, Accessibility trust, System Settings UI automation, and Finder fallback; and `ReplaceKitApp` for the SwiftUI editor-first interface. Keep the read-only undocumented global preference and the macOS 26 Accessibility selectors isolated behind protocols. Keep all writes routed through Apple's System Settings UI and verify every write by refreshing the observed system list.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI, Foundation `PropertyListEncoder` and `PropertyListDecoder`, `UserDefaults`, ApplicationServices Accessibility APIs, Swift Testing, shell packaging script.

---

## Assumptions And Boundaries

- The first release is a local unsigned utility, not a Mac App Store app.
- The supported build path is the installed Command Line Tools: `swift build` and `swift test`. Full Xcode is not installed on the development Mac.
- The deployment target is macOS 14 or later. Live verification is against macOS 26.5.
- Apple's documented plist import and export workflow remains the recovery path: [Back up and share text replacements on Mac](https://support.apple.com/en-mt/guide/mac-help/mchl2a7bd795/mac).
- `NSUserDictionaryReplacementItems` is an observed, undocumented global preference. V1 may read it but must never write it. If it is absent or malformed, show an unsupported-system error and keep manual plist import/export guidance available.
- The verified macOS 26.5 Text Replacements sheet exposes an Accessibility outline whose rows contain two text fields: shortcut then phrase. The add, remove, and done controls are not reliably labeled. The writer must resolve them structurally and verify postconditions after every action.
- Tags use shortcut text as identity. Shortcuts must be unique.

## File Map

```text
Package.swift
.gitignore
README.md
Resources/Info.plist
Scripts/package-app.sh
Sources/
  ReplaceKitCore/
    Models/TextReplacement.swift
    Models/ReplaceKitConfiguration.swift
    Plist/TextReplacementPlistCodec.swift
    Storage/ConfigurationStore.swift
    Storage/SnapshotStore.swift
    Diff/ReplacementDiff.swift
    Apply/TextReplacementGateway.swift
    Apply/ApplyCoordinator.swift
  ReplaceKitMac/
    Preferences/GlobalDefaultsTextReplacementReader.swift
    Preferences/BackupFolderPreference.swift
    Accessibility/AccessibilityTrust.swift
    Accessibility/AXElement.swift
    Accessibility/SystemSettingsTextReplacementWriter.swift
    Fallback/ManualImportService.swift
  ReplaceKitApp/
    ReplaceKitApp.swift
    AppModel.swift
    Views/ContentView.swift
    Views/EditorView.swift
    Views/HistoryView.swift
    Views/DiffPreviewView.swift
    Views/SettingsView.swift
Tests/
  ReplaceKitCoreTests/
    TextReplacementPlistCodecTests.swift
    ConfigurationStoreTests.swift
    SnapshotStoreTests.swift
    ReplacementDiffTests.swift
    ApplyCoordinatorTests.swift
  ReplaceKitMacTests/
    GlobalDefaultsTextReplacementReaderTests.swift
    BackupFolderPreferenceTests.swift
    SystemSettingsTextReplacementWriterIntegrationTests.swift
Tools/
  ReplaceKitAXProbe/main.swift
```

## Milestone 1: Portable Core

### Task 1: Bootstrap The Swift Package

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/ReplaceKitApp/ReplaceKitApp.swift`
- Create: `Tests/ReplaceKitCoreTests/BootstrapTests.swift`

- [ ] **Step 1: Write the package manifest and a failing bootstrap test**

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReplaceKit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ReplaceKit", targets: ["ReplaceKitApp"]),
        .executable(name: "ReplaceKitAXProbe", targets: ["ReplaceKitAXProbe"]),
        .library(name: "ReplaceKitCore", targets: ["ReplaceKitCore"]),
        .library(name: "ReplaceKitMac", targets: ["ReplaceKitMac"]),
    ],
    targets: [
        .target(name: "ReplaceKitCore"),
        .target(name: "ReplaceKitMac", dependencies: ["ReplaceKitCore"]),
        .executableTarget(name: "ReplaceKitApp", dependencies: ["ReplaceKitCore", "ReplaceKitMac"]),
        .executableTarget(name: "ReplaceKitAXProbe", dependencies: ["ReplaceKitMac"]),
        .testTarget(name: "ReplaceKitCoreTests", dependencies: ["ReplaceKitCore"]),
        .testTarget(name: "ReplaceKitMacTests", dependencies: ["ReplaceKitMac", "ReplaceKitCore"]),
    ]
)
```

```swift
// Tests/ReplaceKitCoreTests/BootstrapTests.swift
import Testing
@testable import ReplaceKitCore

@Test func coreModuleLoads() {
    #expect(true)
}
```

- [ ] **Step 2: Run the build to verify it fails because source targets are missing**

Run: `swift test`

Expected: FAIL with a missing source-file error for one or more declared targets.

- [ ] **Step 3: Add minimal source entry points and ignore generated files**

```swift
// Sources/ReplaceKitApp/ReplaceKitApp.swift
import SwiftUI

@main
struct ReplaceKitApp: App {
    var body: some Scene {
        WindowGroup {
            Text("ReplaceKit")
                .frame(minWidth: 720, minHeight: 480)
        }
    }
}
```

```swift
// Sources/ReplaceKitCore/Bootstrap.swift
public enum ReplaceKitCoreModule {}
```

```swift
// Sources/ReplaceKitMac/Bootstrap.swift
public enum ReplaceKitMacModule {}
```

```swift
// Tools/ReplaceKitAXProbe/main.swift
print("ReplaceKitAXProbe")
```

```gitignore
.build/
.DS_Store
outputs/
```

- [ ] **Step 4: Run the build and test**

Run: `swift test && swift build`

Expected: PASS and both executables compile.

- [ ] **Step 5: Commit**

```bash
git add Package.swift .gitignore Sources Tests Tools
git commit -m "build: bootstrap ReplaceKit Swift package"
```

### Task 2: Define Replacement Models And Plist Codec

**Files:**
- Create: `Sources/ReplaceKitCore/Models/TextReplacement.swift`
- Create: `Sources/ReplaceKitCore/Plist/TextReplacementPlistCodec.swift`
- Create: `Tests/ReplaceKitCoreTests/TextReplacementPlistCodecTests.swift`
- Delete: `Sources/ReplaceKitCore/Bootstrap.swift`

- [ ] **Step 1: Write failing codec tests**

```swift
import Foundation
import Testing
@testable import ReplaceKitCore

@Test func roundTripsAppleCompatiblePlist() throws {
    let replacements = [
        TextReplacement(shortcut: ".hello", phrase: "Hello\n世界 👋"),
        TextReplacement(shortcut: "omw", phrase: "On my way!"),
    ]

    let data = try TextReplacementPlistCodec().encode(replacements)
    let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]])

    #expect(plist[0]["replace"] as? String == ".hello")
    #expect(plist[0]["with"] as? String == "Hello\n世界 👋")
    #expect(plist[0]["on"] as? Int == 1)
    #expect(try TextReplacementPlistCodec().decode(data) == replacements)
}

@Test func rejectsDuplicateShortcuts() {
    #expect(throws: ReplacementValidationError.duplicateShortcut(".x")) {
        try TextReplacement.validateUnique([
            TextReplacement(shortcut: ".x", phrase: "one"),
            TextReplacement(shortcut: ".x", phrase: "two"),
        ])
    }
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `swift test --filter TextReplacementPlistCodecTests`

Expected: FAIL because `TextReplacement` and `TextReplacementPlistCodec` do not exist.

- [ ] **Step 3: Implement the model and codec**

```swift
// Sources/ReplaceKitCore/Models/TextReplacement.swift
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
```

```swift
// Sources/ReplaceKitCore/Plist/TextReplacementPlistCodec.swift
import Foundation

public struct TextReplacementPlistCodec: Sendable {
    private struct Record: Codable {
        let replace: String
        let with: String
        let on: Int
    }

    public init() {}

    public func encode(_ replacements: [TextReplacement]) throws -> Data {
        try TextReplacement.validateUnique(replacements)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(replacements.map {
            Record(replace: $0.shortcut, with: $0.phrase, on: $0.isEnabled ? 1 : 0)
        })
    }

    public func decode(_ data: Data) throws -> [TextReplacement] {
        let records = try PropertyListDecoder().decode([Record].self, from: data)
        let replacements = records.map {
            TextReplacement(shortcut: $0.replace, phrase: $0.with, isEnabled: $0.on != 0)
        }
        try TextReplacement.validateUnique(replacements)
        return replacements
    }
}
```

- [ ] **Step 4: Run codec tests**

Run: `swift test --filter TextReplacementPlistCodecTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReplaceKitCore Tests/ReplaceKitCoreTests
git commit -m "feat: add replacement model and plist codec"
```

### Task 3: Persist Tags And App Settings

**Files:**
- Create: `Sources/ReplaceKitCore/Models/ReplaceKitConfiguration.swift`
- Create: `Sources/ReplaceKitCore/Storage/ConfigurationStore.swift`
- Create: `Tests/ReplaceKitCoreTests/ConfigurationStoreTests.swift`

- [ ] **Step 1: Write failing configuration-store tests**

```swift
import Foundation
import Testing
@testable import ReplaceKitCore

@Test func storesTagsSeparatelyFromAppleRecords() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = ConfigurationStore(folder: folder)
    let config = ReplaceKitConfiguration(
        tagsByShortcut: [".hello": ["work", "greeting"]],
        createDailySnapshotOnOpen: true
    )

    try store.save(config)
    #expect(try store.load() == config)
}

@Test func renamingShortcutMigratesTags() {
    let config = ReplaceKitConfiguration(tagsByShortcut: [".old": ["work"]])
    #expect(config.renamingShortcut(from: ".old", to: ".new").tagsByShortcut == [".new": ["work"]])
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `swift test --filter ConfigurationStoreTests`

Expected: FAIL because configuration types do not exist.

- [ ] **Step 3: Implement configuration storage**

```swift
// Sources/ReplaceKitCore/Models/ReplaceKitConfiguration.swift
import Foundation

public struct ReplaceKitConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var tagsByShortcut: [String: Set<String>]
    public var createDailySnapshotOnOpen: Bool

    public init(
        tagsByShortcut: [String: Set<String>] = [:],
        createDailySnapshotOnOpen: Bool = false
    ) {
        self.tagsByShortcut = tagsByShortcut
        self.createDailySnapshotOnOpen = createDailySnapshotOnOpen
    }

    public func renamingShortcut(from oldShortcut: String, to newShortcut: String) -> Self {
        var copy = self
        copy.tagsByShortcut[newShortcut] = copy.tagsByShortcut.removeValue(forKey: oldShortcut)
        return copy
    }
}
```

```swift
// Sources/ReplaceKitCore/Storage/ConfigurationStore.swift
import Foundation

public struct ConfigurationStore: Sendable {
    public let folder: URL
    public init(folder: URL) { self.folder = folder }

    public func load() throws -> ReplaceKitConfiguration {
        let url = folder.appending(path: "replacekit.json")
        guard FileManager.default.fileExists(atPath: url.path()) else { return .init() }
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
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ConfigurationStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReplaceKitCore Tests/ReplaceKitCoreTests
git commit -m "feat: persist ReplaceKit tags and settings"
```

### Task 4: Add Versioned Snapshot Storage

**Files:**
- Create: `Sources/ReplaceKitCore/Storage/SnapshotStore.swift`
- Create: `Tests/ReplaceKitCoreTests/SnapshotStoreTests.swift`

- [ ] **Step 1: Write failing snapshot tests**

```swift
import Foundation
import Testing
@testable import ReplaceKitCore

@Test func writesSnapshotPairAndSkipsDuplicate() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SnapshotStore(folder: folder, codec: .init())
    let replacements = [TextReplacement(shortcut: ".a", phrase: "A")]
    let config = ReplaceKitConfiguration(tagsByShortcut: [".a": ["work"]])
    let now = Date(timeIntervalSince1970: 1_780_406_400)

    let first = try store.writeSnapshot(replacements: replacements, configuration: config, reason: .manual, now: now)
    let second = try store.writeSnapshot(replacements: replacements, configuration: config, reason: .manual, now: now.addingTimeInterval(60))

    #expect(first != nil)
    #expect(second == nil)
    #expect(try store.list().count == 1)
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `swift test --filter SnapshotStoreTests`

Expected: FAIL because `SnapshotStore` does not exist.

- [ ] **Step 3: Implement snapshot pair storage**

```swift
// Sources/ReplaceKitCore/Storage/SnapshotStore.swift
import Foundation

public enum SnapshotReason: String, Codable, Sendable { case manual, beforeEdit, dailyOpen }

public struct SnapshotMetadata: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let schemaVersion: Int
    public let tagsByShortcut: [String: Set<String>]
    public let reason: SnapshotReason
}

public struct Snapshot: Equatable, Sendable {
    public let plistURL: URL
    public let metadataURL: URL
    public let metadata: SnapshotMetadata
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataData = try encoder.encode(metadata)

        if let latest = try list().first,
           try Data(contentsOf: latest.plistURL) == plist,
           latest.metadata.tagsByShortcut == metadata.tagsByShortcut {
            return nil
        }

        let snapshots = folder.appending(path: "snapshots")
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stem = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        let plistURL = snapshots.appending(path: "\(stem).plist")
        let metadataURL = snapshots.appending(path: "\(stem).metadata.json")
        try plist.write(to: plistURL, options: .atomic)
        try metadataData.write(to: metadataURL, options: .atomic)
        return Snapshot(plistURL: plistURL, metadataURL: metadataURL, metadata: metadata)
    }

    public func list() throws -> [Snapshot] {
        let snapshots = folder.appending(path: "snapshots")
        guard FileManager.default.fileExists(atPath: snapshots.path()) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try urls.filter { $0.lastPathComponent.hasSuffix(".metadata.json") }.map { metadataURL in
            let metadata = try decoder.decode(SnapshotMetadata.self, from: Data(contentsOf: metadataURL))
            let stem = metadataURL.lastPathComponent.replacingOccurrences(of: ".metadata.json", with: "")
            return Snapshot(
                plistURL: snapshots.appending(path: "\(stem).plist"),
                metadataURL: metadataURL,
                metadata: metadata
            )
        }.sorted { $0.metadata.timestamp > $1.metadata.timestamp }
    }
}
```

- [ ] **Step 4: Run snapshot tests**

Run: `swift test --filter SnapshotStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReplaceKitCore Tests/ReplaceKitCoreTests
git commit -m "feat: add versioned snapshot storage"
```

### Task 5: Calculate Restore And Import Diffs

**Files:**
- Create: `Sources/ReplaceKitCore/Diff/ReplacementDiff.swift`
- Create: `Tests/ReplaceKitCoreTests/ReplacementDiffTests.swift`

- [ ] **Step 1: Write failing diff tests**

```swift
import Foundation
import Testing
@testable import ReplaceKitCore

@Test func reportsAddedEditedAndDeletedRows() {
    let current = [
        TextReplacement(shortcut: ".keep", phrase: "old"),
        TextReplacement(shortcut: ".delete", phrase: "remove"),
    ]
    let proposed = [
        TextReplacement(shortcut: ".keep", phrase: "new"),
        TextReplacement(shortcut: ".add", phrase: "insert"),
    ]

    let diff = ReplacementDiff.compare(current: current, proposed: proposed)
    #expect(diff.added.map(\.shortcut) == [".add"])
    #expect(diff.deleted.map(\.shortcut) == [".delete"])
    #expect(diff.edited.map(\.after.shortcut) == [".keep"])
}

@Test func detectsChangedBasisBeforeApply() {
    let preview = [TextReplacement(shortcut: ".a", phrase: "old")]
    let observed = [TextReplacement(shortcut: ".a", phrase: "changed elsewhere")]
    #expect(ReplacementDiff.basisChanged(preview: preview, observed: observed))
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `swift test --filter ReplacementDiffTests`

Expected: FAIL because `ReplacementDiff` does not exist.

- [ ] **Step 3: Implement deterministic diffing**

```swift
// Sources/ReplaceKitCore/Diff/ReplacementDiff.swift
import Foundation

public struct EditedReplacement: Equatable, Sendable {
    public let before: TextReplacement
    public let after: TextReplacement
}

public struct ReplacementDiff: Equatable, Sendable {
    public let added: [TextReplacement]
    public let edited: [EditedReplacement]
    public let deleted: [TextReplacement]

    public static func compare(current: [TextReplacement], proposed: [TextReplacement]) -> Self {
        let old = Dictionary(uniqueKeysWithValues: current.map { ($0.shortcut, $0) })
        let new = Dictionary(uniqueKeysWithValues: proposed.map { ($0.shortcut, $0) })
        let added = Set(new.keys).subtracting(old.keys).compactMap { new[$0] }.sorted { $0.shortcut < $1.shortcut }
        let deleted = Set(old.keys).subtracting(new.keys).compactMap { old[$0] }.sorted { $0.shortcut < $1.shortcut }
        let edited = Set(old.keys).intersection(new.keys).compactMap { key -> EditedReplacement? in
            guard let before = old[key], let after = new[key], before != after else { return nil }
            return EditedReplacement(before: before, after: after)
        }.sorted { $0.after.shortcut < $1.after.shortcut }
        return .init(added: added, edited: edited, deleted: deleted)
    }

    public static func basisChanged(preview: [TextReplacement], observed: [TextReplacement]) -> Bool {
        Set(preview) != Set(observed)
    }
}
```

- [ ] **Step 4: Run diff tests**

Run: `swift test --filter ReplacementDiffTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReplaceKitCore Tests/ReplaceKitCoreTests
git commit -m "feat: add deterministic replacement diffs"
```

## Milestone 2: macOS Integration

### Task 6: Read Current macOS Replacements Without Writing Preferences

**Files:**
- Create: `Sources/ReplaceKitCore/Apply/TextReplacementGateway.swift`
- Create: `Sources/ReplaceKitMac/Preferences/GlobalDefaultsTextReplacementReader.swift`
- Create: `Sources/ReplaceKitMac/Preferences/BackupFolderPreference.swift`
- Create: `Tests/ReplaceKitMacTests/GlobalDefaultsTextReplacementReaderTests.swift`
- Create: `Tests/ReplaceKitMacTests/BackupFolderPreferenceTests.swift`
- Delete: `Sources/ReplaceKitMac/Bootstrap.swift`

- [ ] **Step 1: Write failing reader tests with injected preference records**

```swift
import Foundation
import Testing
@testable import ReplaceKitCore
@testable import ReplaceKitMac

@Test func convertsObservedGlobalDefaultsShape() throws {
    let reader = GlobalDefaultsTextReplacementReader(loadRecords: {
        [
            ["replace": ".num", "with": 123456, "on": 1],
            ["replace": "omw", "with": "On my way!", "on": 1],
        ]
    })

    #expect(try reader.fetchAll() == [
        TextReplacement(shortcut: ".num", phrase: "123456"),
        TextReplacement(shortcut: "omw", phrase: "On my way!"),
    ])
}

@Test func rejectsMissingPreference() {
    let reader = GlobalDefaultsTextReplacementReader(loadRecords: { nil })
    #expect(throws: GlobalDefaultsReaderError.preferenceUnavailable) {
        try reader.fetchAll()
    }
}

@Test func persistsChosenBackupFolderPath() {
    let suite = "replacekit-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preference = BackupFolderPreference(defaults: defaults)
    let folder = URL(filePath: "/tmp/replacekit-backups")

    preference.save(folder)

    #expect(preference.load() == folder)
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `swift test --filter GlobalDefaultsTextReplacementReaderTests`

Expected: FAIL because the reader protocol and adapter do not exist.

- [ ] **Step 3: Implement the protocol and isolated read-only adapter**

```swift
// Sources/ReplaceKitCore/Apply/TextReplacementGateway.swift
public protocol TextReplacementReading: Sendable {
    func fetchAll() throws -> [TextReplacement]
}

public protocol TextReplacementWriting: Sendable {
    func add(_ replacement: TextReplacement) async throws
    func update(originalShortcut: String, replacement: TextReplacement) async throws
    func delete(shortcut: String) async throws
}
```

```swift
// Sources/ReplaceKitMac/Preferences/GlobalDefaultsTextReplacementReader.swift
import Foundation
import ReplaceKitCore

public enum GlobalDefaultsReaderError: Error, Equatable { case preferenceUnavailable, malformedRecord }

public struct GlobalDefaultsTextReplacementReader: TextReplacementReading, @unchecked Sendable {
    public typealias LoadRecords = () -> [[String: Any]]?
    private let loadRecords: LoadRecords

    public init(loadRecords: @escaping LoadRecords = {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["NSUserDictionaryReplacementItems"] as? [[String: Any]]
    }) {
        self.loadRecords = loadRecords
    }

    public func fetchAll() throws -> [TextReplacement] {
        guard let records = loadRecords() else { throw GlobalDefaultsReaderError.preferenceUnavailable }
        let replacements = try records.map { record -> TextReplacement in
            guard let shortcut = record["replace"] as? String, let phrase = record["with"] else {
                throw GlobalDefaultsReaderError.malformedRecord
            }
            return TextReplacement(
                shortcut: shortcut,
                phrase: String(describing: phrase),
                isEnabled: (record["on"] as? Int ?? 1) != 0
            )
        }.sorted { $0.shortcut < $1.shortcut }
        try TextReplacement.validateUnique(replacements)
        return replacements
    }
}
```

```swift
// Sources/ReplaceKitMac/Preferences/BackupFolderPreference.swift
import Foundation

public struct BackupFolderPreference: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "backupFolderPath"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> URL? {
        defaults.string(forKey: key).map(URL.init(filePath:))
    }

    public func save(_ folder: URL?) {
        defaults.set(folder?.path(), forKey: key)
    }
}
```

- [ ] **Step 4: Run adapter tests**

Run: `swift test --filter ReplaceKitMacTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReplaceKitCore Sources/ReplaceKitMac Tests/ReplaceKitMacTests
git commit -m "feat: read current macOS replacements safely"
```

### Task 7: Add Accessibility Trust And A Diagnostic Probe

**Files:**
- Create: `Sources/ReplaceKitMac/Accessibility/AccessibilityTrust.swift`
- Create: `Sources/ReplaceKitMac/Accessibility/AXElement.swift`
- Modify: `Tools/ReplaceKitAXProbe/main.swift`

- [ ] **Step 1: Implement the trust wrapper and AX tree wrapper**

```swift
// Sources/ReplaceKitMac/Accessibility/AccessibilityTrust.swift
import ApplicationServices

public struct AccessibilityTrust: Sendable {
    public init() {}

    public func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
```

```swift
// Sources/ReplaceKitMac/Accessibility/AXElement.swift
import ApplicationServices
import Foundation

public struct AXElement {
    public let rawValue: AXUIElement
    public init(_ rawValue: AXUIElement) { self.rawValue = rawValue }

    public func value(_ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(rawValue, attribute, &value) == .success else { return nil }
        return value
    }

    public func string(_ attribute: CFString) -> String? {
        value(attribute) as? String
    }

    public func elements(_ attribute: CFString) -> [AXElement] {
        guard let values = value(attribute) as? [AXUIElement] else { return [] }
        return values.map(AXElement.init)
    }

    public var children: [AXElement] { elements(kAXChildrenAttribute as CFString) }
    public var role: String? { string(kAXRoleAttribute as CFString) }
    public var subrole: String? { string(kAXSubroleAttribute as CFString) }
    public var title: String? { string(kAXTitleAttribute as CFString) }
    public var value: String? { string(kAXValueAttribute as CFString) }
    public var isEnabled: Bool { (value(kAXEnabledAttribute as CFString) as? Bool) ?? false }
    public var position: CGPoint? { point(kAXPositionAttribute as CFString) }
    public var size: CGSize? { size(kAXSizeAttribute as CFString) }

    public func descendants() -> [AXElement] {
        children + children.flatMap { $0.descendants() }
    }

    private func point(_ attribute: CFString) -> CGPoint? {
        guard let value = value(attribute) as? AXValue, AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func size(_ attribute: CFString) -> CGSize? {
        guard let value = value(attribute) as? AXValue, AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    public func press() throws {
        let error = AXUIElementPerformAction(rawValue, kAXPressAction as CFString)
        guard error == .success else { throw AXElementError.actionFailed(error.rawValue) }
    }

    public func setStringValue(_ value: String) throws {
        try set(attribute: kAXValueAttribute as CFString, value: value as CFString)
    }

    public func select() throws {
        try set(attribute: kAXSelectedAttribute as CFString, value: kCFBooleanTrue)
    }

    private func set(attribute: CFString, value: CFTypeRef) throws {
        let error = AXUIElementSetAttributeValue(rawValue, attribute, value)
        guard error == .success else { throw AXElementError.setFailed(error.rawValue) }
    }
}

public enum AXElementError: Error { case actionFailed(Int32), setFailed(Int32) }
```

- [ ] **Step 2: Replace the probe placeholder with a tree dumper**

```swift
// Tools/ReplaceKitAXProbe/main.swift
import AppKit
import ApplicationServices
import ReplaceKitMac

guard AccessibilityTrust().isTrusted(prompt: true) else {
    fputs("Grant Accessibility permission, then run again.\n", stderr)
    exit(2)
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else {
    fputs("Open System Settings first.\n", stderr)
    exit(3)
}

func dump(_ element: AXElement, depth: Int = 0) {
    print("\(String(repeating: "  ", count: depth))\(element.role ?? "?") | \(element.title ?? "") | \(element.value ?? "")")
    for child in element.children { dump(child, depth: depth + 1) }
}

dump(AXElement(AXUIElementCreateApplication(app.processIdentifier)))
```

- [ ] **Step 3: Build and manually inspect the current sheet**

Run:

```bash
swift build --product ReplaceKitAXProbe
swift run ReplaceKitAXProbe
```

Expected after opening System Settings > Keyboard > Text Replacements: an AX sheet containing an outline; each replacement row contains two text fields. Save no private user phrases in the repository.

- [ ] **Step 4: Commit**

```bash
git add Sources/ReplaceKitMac Tools
git commit -m "feat: add accessibility trust and AX probe"
```

### Task 8: Apply Routine Changes Through System Settings

**Files:**
- Create: `Sources/ReplaceKitMac/Accessibility/SystemSettingsTextReplacementWriter.swift`
- Create: `Tests/ReplaceKitMacTests/SystemSettingsTextReplacementWriterIntegrationTests.swift`

- [ ] **Step 1: Write opt-in integration tests that always clean up**

```swift
import Foundation
import Testing
@testable import ReplaceKitCore
@testable import ReplaceKitMac

@Test func addsAndDeletesReplacementThroughSystemSettings() async throws {
    guard ProcessInfo.processInfo.environment["REPLACEKIT_RUN_AX_TESTS"] == "1" else { return }
    let shortcut = ".replacekit-\(UUID().uuidString.prefix(8))"
    let replacement = TextReplacement(shortcut: shortcut, phrase: "ReplaceKit integration test")
    let reader = GlobalDefaultsTextReplacementReader()
    let writer = SystemSettingsTextReplacementWriter()

    do {
        try await writer.add(replacement)
        #expect(try await eventually { try reader.fetchAll().contains(replacement) })
        try await writer.delete(shortcut: shortcut)
        #expect(try await eventually { try !reader.fetchAll().contains(replacement) })
    } catch {
        try? await writer.delete(shortcut: shortcut)
        throw error
    }
}

func eventually(_ predicate: () throws -> Bool) async throws -> Bool {
    for _ in 0..<20 {
        if try predicate() { return true }
        try await Task.sleep(for: .milliseconds(100))
    }
    return false
}
```

- [ ] **Step 2: Implement the writer with one macOS-specific selector boundary**

```swift
// Sources/ReplaceKitMac/Accessibility/SystemSettingsTextReplacementWriter.swift
import AppKit
import ApplicationServices
import ReplaceKitCore

public enum SystemSettingsWriterError: Error {
    case accessibilityPermissionMissing
    case settingsUnavailable
    case textReplacementsSheetUnavailable
    case unexpectedSheetShape
    case replacementNotFound(String)
    case postconditionFailed
}

public actor SystemSettingsTextReplacementWriter: TextReplacementWriting {
    private let trust = AccessibilityTrust()
    private let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    public init() {}

    public func add(_ replacement: TextReplacement) async throws {
        let sheet = try await resolvedSheet()
        let controls = try MacOS26TextReplacementSheet(sheet: sheet)
        try controls.add(shortcut: replacement.shortcut, phrase: replacement.phrase)
    }

    public func update(originalShortcut: String, replacement: TextReplacement) async throws {
        let sheet = try await resolvedSheet()
        let controls = try MacOS26TextReplacementSheet(sheet: sheet)
        try controls.update(originalShortcut: originalShortcut, shortcut: replacement.shortcut, phrase: replacement.phrase)
    }

    public func delete(shortcut: String) async throws {
        let sheet = try await resolvedSheet()
        let controls = try MacOS26TextReplacementSheet(sheet: sheet)
        try controls.delete(shortcut: shortcut)
    }

    private func resolvedSheet() async throws -> AXElement {
        guard trust.isTrusted(prompt: true) else { throw SystemSettingsWriterError.accessibilityPermissionMissing }
        NSWorkspace.shared.open(settingsURL)
        return try await SystemSettingsSheetResolver().resolveTextReplacementsSheet(timeout: .seconds(5))
    }
}

struct SystemSettingsSheetResolver {
    func resolveTextReplacementsSheet(timeout: Duration) async throws -> AXElement {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first {
                let root = AXElement(AXUIElementCreateApplication(app.processIdentifier))
                let sheets = root.descendants().filter {
                    $0.role == (kAXSheetRole as String) &&
                    $0.descendants().filter { $0.role == (kAXOutlineRole as String) }.count == 1
                }
                if sheets.count == 1 { return sheets[0] }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw SystemSettingsWriterError.textReplacementsSheetUnavailable
    }
}

struct MacOS26TextReplacementSheet {
    struct Row {
        let element: AXElement
        let shortcut: AXElement
        let phrase: AXElement
    }

    let sheet: AXElement
    let outline: AXElement

    init(sheet: AXElement) throws {
        let outlines = sheet.descendants().filter { $0.role == (kAXOutlineRole as String) }
        guard outlines.count == 1 else { throw SystemSettingsWriterError.unexpectedSheetShape }
        self.sheet = sheet
        self.outline = outlines[0]
    }

    func add(shortcut: String, phrase: String) throws {
        let controls = try controls()
        try controls.add.press()
        guard let row = try rows().last(where: { $0.shortcut.value == "" && $0.phrase.value == "" }) else {
            throw SystemSettingsWriterError.unexpectedSheetShape
        }
        try row.shortcut.setStringValue(shortcut)
        try row.phrase.setStringValue(phrase)
        try controls.done.press()
    }

    func update(originalShortcut: String, shortcut: String, phrase: String) throws {
        let row = try requiredRow(shortcut: originalShortcut)
        try row.element.select()
        try row.shortcut.setStringValue(shortcut)
        try row.phrase.setStringValue(phrase)
        try controls().done.press()
    }

    func delete(shortcut: String) throws {
        let row = try requiredRow(shortcut: shortcut)
        try row.element.select()
        let controls = try controls()
        guard controls.remove.isEnabled else { throw SystemSettingsWriterError.unexpectedSheetShape }
        try controls.remove.press()
        try controls.done.press()
    }

    private func requiredRow(shortcut: String) throws -> Row {
        guard let row = try rows().first(where: { $0.shortcut.value == shortcut }) else {
            throw SystemSettingsWriterError.replacementNotFound(shortcut)
        }
        return row
    }

    private func rows() throws -> [Row] {
        try outline.children.filter { $0.role == (kAXRowRole as String) }.map { element in
            let fields = element.descendants().filter { $0.role == (kAXTextFieldRole as String) }
            guard fields.count == 2 else { throw SystemSettingsWriterError.unexpectedSheetShape }
            return Row(element: element, shortcut: fields[0], phrase: fields[1])
        }
    }

    private func controls() throws -> (add: AXElement, remove: AXElement, done: AXElement) {
        let buttons = sheet.descendants().filter {
            $0.role == (kAXButtonRole as String) && $0.subrole != "AXSortButton"
        }
        let small = buttons.filter { ($0.size?.width ?? .infinity) <= 16 }.sorted {
            ($0.position?.x ?? .infinity) < ($1.position?.x ?? .infinity)
        }
        let wide = buttons.filter { ($0.size?.width ?? 0) > 40 }
        guard small.count == 2, wide.count == 1 else {
            throw SystemSettingsWriterError.unexpectedSheetShape
        }
        return (add: small[0], remove: small[1], done: wide[0])
    }
}
```

Before accepting this adapter, confirm these exact structural rules with `ReplaceKitAXProbe`:

1. Resolve the running app with bundle identifier `com.apple.systempreferences`.
2. Walk the application AX tree and require exactly one sheet containing exactly one outline.
3. Parse each outline row by requiring exactly two descendant text fields: shortcut and phrase.
4. Resolve the add and remove controls only inside that sheet. Require two small adjacent buttons below the outline; add is enabled before selection, remove becomes enabled after selecting a row.
5. Resolve the done control only inside that sheet as the remaining enabled button outside the outline.
6. For add, press add, set the two new row text fields, and press done.
7. For update, select the row whose shortcut matches, set its two text fields, and press done.
8. For delete, select the matching row, press remove, and press done.
9. Throw `unexpectedSheetShape` whenever a structural invariant is not met.

- [ ] **Step 3: Compile without running live mutation tests**

Run: `swift test`

Expected: PASS. The opt-in integration test exits without mutation.

- [ ] **Step 4: Run the opt-in mutation test against a disposable shortcut**

Run:

```bash
REPLACEKIT_RUN_AX_TESTS=1 swift test --filter addsAndDeletesReplacementThroughSystemSettings
```

Expected: PASS after the tester clicks `Text replacements` if the sheet is not already open. System Settings visibly opens. The temporary `.replacekit-...` row is removed before the test exits.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReplaceKitMac Tests/ReplaceKitMacTests
git commit -m "feat: write replacements through System Settings"
```

### Task 9: Add Snapshot-Protected Apply Coordination And Manual Fallback

**Files:**
- Create: `Sources/ReplaceKitCore/Apply/ApplyCoordinator.swift`
- Create: `Sources/ReplaceKitMac/Fallback/ManualImportService.swift`
- Create: `Tests/ReplaceKitCoreTests/ApplyCoordinatorTests.swift`

- [ ] **Step 1: Write failing apply tests with fakes**

```swift
import Testing
@testable import ReplaceKitCore

@Test func snapshotsBeforeRoutineEditAndVerifiesObservedResult() async throws {
    let reader = InMemoryGateway([TextReplacement(shortcut: ".a", phrase: "old")])
    let snapshots = RecordingSnapshotWriter()
    let coordinator = ApplyCoordinator(reader: reader, writer: reader, snapshots: snapshots)

    let result = try await coordinator.apply(.update(
        originalShortcut: ".a",
        replacement: TextReplacement(shortcut: ".a", phrase: "new")
    ), configuration: .init())

    #expect(snapshots.reasons == [.beforeEdit])
    #expect(result.observed == [TextReplacement(shortcut: ".a", phrase: "new")])
}

@Test func permitsExplicitOneTimeUnprotectedEdit() async throws {
    let gateway = InMemoryGateway([])
    let snapshots = RecordingSnapshotWriter(error: TestError.backupFolderUnavailable)
    let coordinator = ApplyCoordinator(reader: gateway, writer: gateway, snapshots: snapshots)

    let result = try await coordinator.apply(
        .add(TextReplacement(shortcut: ".a", phrase: "A")),
        configuration: .init(),
        protection: .unprotectedOnce
    )

    #expect(result.observed == [TextReplacement(shortcut: ".a", phrase: "A")])
}

enum TestError: Error { case backupFolderUnavailable }

final class InMemoryGateway: TextReplacementReading, TextReplacementWriting, @unchecked Sendable {
    private var replacements: [TextReplacement]
    init(_ replacements: [TextReplacement]) { self.replacements = replacements }
    func fetchAll() throws -> [TextReplacement] { replacements }
    func add(_ replacement: TextReplacement) async throws { replacements.append(replacement) }
    func update(originalShortcut: String, replacement: TextReplacement) async throws {
        replacements.removeAll { $0.shortcut == originalShortcut }
        replacements.append(replacement)
    }
    func delete(shortcut: String) async throws { replacements.removeAll { $0.shortcut == shortcut } }
}

final class RecordingSnapshotWriter: SnapshotWriting, @unchecked Sendable {
    private(set) var reasons: [SnapshotReason] = []
    private let error: Error?
    init(error: Error? = nil) { self.error = error }
    func write(replacements: [TextReplacement], configuration: ReplaceKitConfiguration, reason: SnapshotReason) throws {
        if let error { throw error }
        reasons.append(reason)
    }
}
```

- [ ] **Step 2: Implement coordinator protocols and routine apply**

```swift
// Sources/ReplaceKitCore/Apply/ApplyCoordinator.swift
public enum ReplacementMutation: Sendable {
    case add(TextReplacement)
    case update(originalShortcut: String, replacement: TextReplacement)
    case delete(shortcut: String)
}

public enum SnapshotProtection: Equatable, Sendable { case required, unprotectedOnce }

public protocol SnapshotWriting: Sendable {
    func write(
        replacements: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        reason: SnapshotReason
    ) throws
}

extension SnapshotStore: SnapshotWriting {
    public func write(
        replacements: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        reason: SnapshotReason
    ) throws {
        _ = try writeSnapshot(replacements: replacements, configuration: configuration, reason: reason)
    }
}

public struct ApplyResult: Sendable {
    public let observed: [TextReplacement]
}

public enum ApplyCoordinatorError: Error {
    case changedBasis(ReplacementDiff)
    case snapshotUnavailable(String)
    case partialResult(observed: [TextReplacement], message: String)
    case postconditionFailed(expected: [TextReplacement], observed: [TextReplacement])
}

public actor ApplyCoordinator {
    private let reader: any TextReplacementReading
    private let writer: any TextReplacementWriting
    private let snapshots: any SnapshotWriting

    public init(reader: any TextReplacementReading, writer: any TextReplacementWriting, snapshots: any SnapshotWriting) {
        self.reader = reader
        self.writer = writer
        self.snapshots = snapshots
    }

    public func apply(
        _ mutation: ReplacementMutation,
        configuration: ReplaceKitConfiguration,
        protection: SnapshotProtection = .required
    ) async throws -> ApplyResult {
        let before = try reader.fetchAll()
        try protect(before, configuration: configuration, protection: protection)
        let expected = applying(mutation, to: before)
        do {
            try await execute(mutation)
        } catch {
            throw ApplyCoordinatorError.partialResult(
                observed: (try? reader.fetchAll()) ?? [],
                message: String(describing: error)
            )
        }
        return try await verifiedResult(expected: expected)
    }

    public func apply(
        proposed: [TextReplacement],
        previewBasis: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        protection: SnapshotProtection = .required
    ) async throws -> ApplyResult {
        let current = try reader.fetchAll()
        guard !ReplacementDiff.basisChanged(preview: previewBasis, observed: current) else {
            throw ApplyCoordinatorError.changedBasis(.compare(current: current, proposed: proposed))
        }
        try protect(current, configuration: configuration, protection: protection)
        let diff = ReplacementDiff.compare(current: current, proposed: proposed)
        let mutations =
            diff.deleted.map { ReplacementMutation.delete(shortcut: $0.shortcut) } +
            diff.edited.map { ReplacementMutation.update(originalShortcut: $0.before.shortcut, replacement: $0.after) } +
            diff.added.map(ReplacementMutation.add)
        do {
            for mutation in mutations { try await execute(mutation) }
        } catch {
            throw ApplyCoordinatorError.partialResult(
                observed: (try? reader.fetchAll()) ?? [],
                message: String(describing: error)
            )
        }
        return try await verifiedResult(expected: proposed)
    }

    private func protect(
        _ replacements: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        protection: SnapshotProtection
    ) throws {
        guard protection == .required else { return }
        do {
            try snapshots.write(replacements: replacements, configuration: configuration, reason: .beforeEdit)
        } catch {
            throw ApplyCoordinatorError.snapshotUnavailable(String(describing: error))
        }
    }

    private func execute(_ mutation: ReplacementMutation) async throws {
        switch mutation {
        case let .add(replacement): try await writer.add(replacement)
        case let .update(shortcut, replacement): try await writer.update(originalShortcut: shortcut, replacement: replacement)
        case let .delete(shortcut): try await writer.delete(shortcut: shortcut)
        }
    }

    private func applying(_ mutation: ReplacementMutation, to replacements: [TextReplacement]) -> [TextReplacement] {
        var values = Dictionary(uniqueKeysWithValues: replacements.map { ($0.shortcut, $0) })
        switch mutation {
        case let .add(replacement): values[replacement.shortcut] = replacement
        case let .update(shortcut, replacement):
            values.removeValue(forKey: shortcut)
            values[replacement.shortcut] = replacement
        case let .delete(shortcut): values.removeValue(forKey: shortcut)
        }
        return values.values.sorted { $0.shortcut < $1.shortcut }
    }

    private func verifiedResult(expected: [TextReplacement]) async throws -> ApplyResult {
        let expected = expected.sorted { $0.shortcut < $1.shortcut }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            let observed = try reader.fetchAll().sorted { $0.shortcut < $1.shortcut }
            if observed == expected { return ApplyResult(observed: observed) }
            try await Task.sleep(for: .milliseconds(100))
        }
        let observed = try reader.fetchAll().sorted { $0.shortcut < $1.shortcut }
        throw ApplyCoordinatorError.postconditionFailed(expected: expected, observed: observed)
    }
}
```

Extend `ApplyCoordinatorTests.swift` with:

- Writer failure still records the pre-change snapshot.
- Observed state mismatch returns a visible partial-result error.
- Guarded apply rejects a changed basis and returns a new `ReplacementDiff` for confirmation.
- Required protection propagates a backup-folder failure without attempting the write.

- [ ] **Step 3: Implement fallback plist export**

```swift
// Sources/ReplaceKitMac/Fallback/ManualImportService.swift
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
```

- [ ] **Step 4: Run tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: protect edits with snapshots and fallback export"
```

## Milestone 3: Editor-First App

### Task 10: Build App State And The Editor Window

**Files:**
- Create: `Sources/ReplaceKitApp/AppModel.swift`
- Create: `Sources/ReplaceKitApp/Views/ContentView.swift`
- Create: `Sources/ReplaceKitApp/Views/EditorView.swift`
- Modify: `Sources/ReplaceKitApp/ReplaceKitApp.swift`

- [ ] **Step 1: Implement one observable app model**

Create `AppModel` as an `@MainActor @Observable` type. It owns:

```swift
var replacements: [TextReplacement] = []
var configuration = ReplaceKitConfiguration()
var selectedShortcut: String?
var sidebarSelection: SidebarSelection? = .all
var searchText = ""
var backupFolder: URL?
var errorMessage: String?
var fallbackPlistURL: URL?
var pendingUnprotectedEdit: PendingRoutineEdit?
```

Define `SidebarSelection` as:

```swift
enum SidebarSelection: Hashable {
    case all
    case tag(String)
    case history
    case settings
}

struct PendingRoutineEdit {
    let mutation: ReplacementMutation
    let nextConfiguration: ReplaceKitConfiguration
}
```

Add these methods with direct dependencies injected in the initializer:

```swift
func refresh()
func chooseBackupFolder()
func add(shortcut: String, phrase: String, tags: Set<String>) async
func update(originalShortcut: String, shortcut: String, phrase: String, tags: Set<String>) async
func delete(shortcut: String) async
func applyPendingMutationWithoutSnapshot() async
func backUpNow()
func exportFallbackPlist()
```

Use this apply boundary so every routine edit follows the same protected path:

```swift
private struct MissingSnapshotWriter: SnapshotWriting {
    func write(
        replacements: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        reason: SnapshotReason
    ) throws {
        throw AppModelError.backupFolderUnavailable
    }
}

enum AppModelError: Error { case backupFolderUnavailable }

private func snapshotWriter() -> any SnapshotWriting {
    guard let backupFolder else { return MissingSnapshotWriter() }
    return SnapshotStore(folder: backupFolder, codec: .init())
}

private func apply(
    _ edit: PendingRoutineEdit,
    protection: SnapshotProtection = .required
) async {
    let coordinator = ApplyCoordinator(reader: reader, writer: writer, snapshots: snapshotWriter())
    do {
        replacements = try await coordinator.apply(
            edit.mutation,
            configuration: configuration,
            protection: protection
        ).observed
        configuration = edit.nextConfiguration
        if let backupFolder { try ConfigurationStore(folder: backupFolder).save(configuration) }
        pendingUnprotectedEdit = nil
    } catch ApplyCoordinatorError.snapshotUnavailable {
        pendingUnprotectedEdit = edit
        errorMessage = "Choose a writable backup folder or apply this edit once without a snapshot."
    } catch ApplyCoordinatorError.partialResult(let observed, let message) {
        replacements = observed
        errorMessage = "System Settings only applied part of the change: \(message)"
        exportFallbackPlist()
    } catch {
        errorMessage = String(describing: error)
    }
}
```

Each add, update, and delete method builds a `PendingRoutineEdit` with the tag mapping after that mutation, then calls `apply(_:)`. `applyPendingMutationWithoutSnapshot()` retries the retained edit with `.unprotectedOnce`. `exportFallbackPlist()` writes the currently observed rows through `ManualImportService` into the selected backup folder, or `FileManager.default.temporaryDirectory` when no writable backup folder exists, and stores the result in `fallbackPlistURL`. Load `backupFolder` from `BackupFolderPreference` during startup. `chooseBackupFolder()` uses `NSOpenPanel` with `canChooseDirectories = true`, saves the chosen path through `BackupFolderPreference`, and reloads `replacekit.json` from that folder. When external changes introduce unknown shortcuts, show those rows without tags and preserve unmatched mappings until the user resolves them.

- [ ] **Step 2: Implement the editor-first layout**

```swift
// Sources/ReplaceKitApp/Views/ContentView.swift
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.sidebarSelection) {
                Text("All").tag(SidebarSelection.all)
                Section("Tags") {
                    ForEach(model.allTags, id: \.self) { tag in
                        Text(tag).tag(SidebarSelection.tag(tag))
                    }
                }
            }
        } detail: {
            EditorView(model: model)
        }
    }
}
```

Implement `EditorView` with:

- A search field bound to `searchText`.
- `+ Add`, `Import`, and `Back Up Now` toolbar buttons.
- A `Table` with shortcut, phrase preview, and comma-separated tags.
- An inspector form for the selected row with Save and Delete actions.
- A visible setup state when `backupFolder == nil`.
- An alert bound to `errorMessage`.

- [ ] **Step 3: Wire app startup**

```swift
// Sources/ReplaceKitApp/ReplaceKitApp.swift
import SwiftUI

@main
struct ReplaceKitApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 560)
                .task { model.refresh() }
        }
    }
}
```

- [ ] **Step 4: Build and launch**

Run: `swift build && swift run ReplaceKit`

Expected: The editor-first window loads the current macOS replacement list. Search and tag filtering work. Without a selected backup folder, edits remain blocked.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReplaceKitApp
git commit -m "feat: add editor-first ReplaceKit window"
```

### Task 11: Add History, Diff Preview, Settings, And Fallback UX

**Files:**
- Create: `Sources/ReplaceKitApp/Views/HistoryView.swift`
- Create: `Sources/ReplaceKitApp/Views/DiffPreviewView.swift`
- Create: `Sources/ReplaceKitApp/Views/SettingsView.swift`
- Modify: `Sources/ReplaceKitApp/AppModel.swift`
- Modify: `Sources/ReplaceKitApp/ReplaceKitApp.swift`
- Modify: `Sources/ReplaceKitApp/Views/ContentView.swift`

- [ ] **Step 1: Add model methods for guarded operations**

Extend `AppModel` with:

```swift
var snapshots: [Snapshot] = []
var pendingDiff: ReplacementDiff?
var pendingProposal: [TextReplacement]?
var isShowingDiffPreview = false

func loadHistory()
func importPlist()
func previewRestore(_ snapshot: Snapshot)
func previewDelete(shortcuts: Set<String>)
func confirmPendingBulkApply() async
func exportFallbackPlist()
func createDailySnapshotIfEnabled()
```

For import, use `NSOpenPanel` restricted to `plist`. For restore, decode the selected snapshot plist. Before applying a pending proposal, call `ApplyCoordinator.apply(proposed:previewBasis:configuration:)`; when it reports a changed basis, replace `pendingDiff` with the recalculated diff and require confirmation again. Call `createDailySnapshotIfEnabled()` once during app startup after loading the selected folder; `SnapshotStore` suppresses duplicate content.

Change the startup task to:

```swift
.task {
    model.refresh()
    model.createDailySnapshotIfEnabled()
}
```

- [ ] **Step 2: Implement history and diff screens**

`HistoryView` lists snapshot timestamp, reason, and plist filename with `Preview Restore`.

`DiffPreviewView` shows three sections:

```text
Added       shortcut -> phrase
Edited      shortcut -> old phrase / new phrase
Deleted     shortcut -> phrase
```

It has `Cancel` and `Apply Changes` actions. Do not hide deletions.

Update `ContentView` by adding `History` and `Settings` sidebar rows and switching the detail:

```swift
Section {
    Text("History").tag(SidebarSelection.history)
    Text("Settings").tag(SidebarSelection.settings)
}

switch model.sidebarSelection {
case .all?, .tag?: EditorView(model: model)
case .history?: HistoryView(model: model)
case .settings?: SettingsView(model: model)
case nil: EditorView(model: model)
}
```

- [ ] **Step 3: Implement settings and fallback guidance**

`SettingsView` includes:

- Current backup folder and `Choose Folder`.
- `Create at most one daily snapshot when app opens`, disabled by default.
- Accessibility status and `Request Accessibility Permission`.
- `Open Keyboard Settings`.
- A fallback panel when `fallbackPlistURL != nil`: reveal `property list.plist` in Finder and show Apple's drag-in instructions.
- A warning panel when `pendingUnprotectedEdit != nil`: choose a writable backup folder or explicitly click `Apply Once Without Snapshot`.

- [ ] **Step 4: Build and manually walk through guarded UX without applying**

Run: `swift run ReplaceKit`

Expected:

- Choosing a folder creates or loads `replacekit.json`.
- `Back Up Now` creates a plist and metadata pair.
- Import and restore show a diff before any write.
- Deletions are visibly listed.
- The daily snapshot toggle persists.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReplaceKitApp
git commit -m "feat: add history diff preview and fallback UX"
```

### Task 12: Package A Finder-Launchable App And Verify V1

**Files:**
- Create: `Resources/Info.plist`
- Create: `Scripts/package-app.sh`
- Create: `README.md`

- [ ] **Step 1: Add app metadata and packaging script**

```xml
<!-- Resources/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ReplaceKit</string>
  <key>CFBundleIdentifier</key><string>local.replacekit.app</string>
  <key>CFBundleName</key><string>ReplaceKit</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
```

```bash
#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product ReplaceKit
APP="$PWD/outputs/ReplaceKit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/ReplaceKit" "$APP/Contents/MacOS/ReplaceKit"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
printf '%s\n' "$APP"
```

- [ ] **Step 2: Document build and recovery workflow**

Add `README.md` with:

- `swift test`
- `Scripts/package-app.sh`
- `open outputs/ReplaceKit.app`
- The one-time Accessibility permission requirement.
- The user-chosen backup folder structure.
- The fallback plist drag-in steps from Apple's documented workflow.
- A warning that ReplaceKit reads an undocumented global preference and may need an adapter update after a macOS release.

- [ ] **Step 3: Run all automated verification**

Run:

```bash
swift test
swift build
Scripts/package-app.sh
codesign --verify --deep --strict outputs/ReplaceKit.app
```

Expected: PASS and `outputs/ReplaceKit.app` exists.

- [ ] **Step 4: Run guarded live macOS verification**

Run:

```bash
REPLACEKIT_RUN_AX_TESTS=1 swift test --filter addsAndDeletesReplacementThroughSystemSettings
open outputs/ReplaceKit.app
```

Expected:

- Disposable Accessibility mutation test passes and removes its row.
- App reads the current replacement list.
- Search and tags work.
- Manual backup creates a snapshot pair.
- Add one disposable replacement, edit it, then delete it; each action writes a pre-change snapshot.
- Import and restore require a diff preview.
- Removing backup-folder access blocks protected edits and visibly offers a one-time unprotected edit.
- Forced automation failure creates `property list.plist` and reveals the manual fallback.

- [ ] **Step 5: Run the manual Apple sync check**

Add a disposable replacement on Mac through ReplaceKit. Confirm it appears on an iPhone signed into the same Apple Account with iCloud Drive enabled. Remove the disposable replacement through ReplaceKit and confirm cleanup.

- [ ] **Step 6: Commit**

```bash
git add Resources Scripts README.md
git commit -m "build: package Finder-launchable ReplaceKit app"
```

## Final Verification

Run:

```bash
git status --short
swift test
swift build
Scripts/package-app.sh
codesign --verify --deep --strict outputs/ReplaceKit.app
```

Expected:

- Working tree is clean.
- Automated tests pass.
- Debug build passes.
- Finder-launchable app bundle is ad-hoc signed and passes verification.

Then repeat the disposable live AX test and the manual iPhone sync check from Task 12.
