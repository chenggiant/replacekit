import Darwin
import Foundation
import ReplaceKitCore
import ReplaceKitMac

var failures = 0

@MainActor
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("PASS: \(message)")
    } else {
        failures += 1
        print("FAIL: \(message)")
    }
}

@MainActor
func checkThrows(_ message: String, _ operation: () throws -> Void) {
    do {
        try operation()
        failures += 1
        print("FAIL: \(message)")
    } catch {
        print("PASS: \(message)")
    }
}

func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "replacekit-tests-\(UUID().uuidString)")
}

@MainActor
func testPlistCodec() throws {
    let replacements = [
        TextReplacement(shortcut: ".hello", phrase: "Hello\n世界 👋"),
        TextReplacement(shortcut: "omw", phrase: "On my way!"),
    ]
    let codec = TextReplacementPlistCodec()
    let data = try codec.encode(replacements)
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]

    check(plist?[0]["replace"] as? String == ".hello", "plist uses Apple's replace key")
    check(plist?[0]["with"] as? String == "Hello\n世界 👋", "plist preserves multiline Unicode phrase")
    check(plist?[0]["on"] as? Int == 1, "plist writes enabled marker")
    let decoded = try codec.decode(data)
    check(decoded == replacements, "plist round trips replacements")
    checkThrows("duplicate shortcuts are rejected") {
        try TextReplacement.validateUnique([
            .init(shortcut: ".x", phrase: "one"),
            .init(shortcut: ".x", phrase: "two"),
        ])
    }
}

@MainActor
func testConfigurationStore() throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ConfigurationStore(folder: folder)
    let configuration = ReplaceKitConfiguration(
        tagsByShortcut: [".hello": ["work", "greeting"]],
        createDailySnapshotOnOpen: true,
        writeMode: .directDefaultsExperimental,
        systemSettingsApplyMode: .standard
    )

    try store.save(configuration)
    let loaded = try store.load()
    check(loaded == configuration, "configuration round trips tags and settings")
    check(
        configuration.renamingShortcut(from: ".hello", to: ".hi").tagsByShortcut == [".hi": ["work", "greeting"]],
        "renaming shortcut migrates tags"
    )

    let legacyConfigurationData = """
    {
      "schemaVersion" : 1,
      "tagsByShortcut" : {
        ".legacy" : ["old"]
      },
      "createDailySnapshotOnOpen" : true
    }
    """.data(using: .utf8)!
    let legacyConfiguration = try JSONDecoder().decode(
        ReplaceKitConfiguration.self,
        from: legacyConfigurationData
    )
    check(
        legacyConfiguration.writeMode == .systemSettings,
        "legacy configuration defaults to System Settings write mode"
    )
    check(
        legacyConfiguration.systemSettingsApplyMode == .quiet,
        "legacy configuration defaults to quiet System Settings apply"
    )
    check(
        ReplacementWriteMode.systemSettings.displayName == "System Settings + iCloud (Recommended)",
        "System Settings mode is presented as the recommended sync path"
    )
    check(
        ReplacementWriteMode.directDefaultsExperimental.displayName == "Local Only (Experimental)",
        "direct defaults mode is presented as local-only"
    )
    check(
        ReplacementWriteMode.systemSettings.saveActionTitle == "Save to Mac & iCloud",
        "System Settings mode save action describes its outcome"
    )
    check(
        ReplacementWriteMode.directDefaultsExperimental.saveActionTitle == "Save Locally",
        "direct defaults mode save action describes its outcome"
    )
}

@MainActor
func testSnapshotStore() throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = SnapshotStore(folder: folder, codec: .init())
    let replacements = [TextReplacement(shortcut: ".a", phrase: "A")]
    let configuration = ReplaceKitConfiguration(tagsByShortcut: [".a": ["work"]])
    let now = Date(timeIntervalSince1970: 1_780_406_400)

    let first = try store.writeSnapshot(
        replacements: replacements,
        configuration: configuration,
        reason: .manual,
        now: now
    )
    let duplicate = try store.writeSnapshot(
        replacements: replacements,
        configuration: configuration,
        reason: .beforeEdit,
        now: now.addingTimeInterval(60)
    )

    check(first != nil, "first snapshot writes plist and metadata")
    check(duplicate == nil, "identical snapshot content and tags are deduplicated")
    let snapshots = try store.list()
    check(snapshots.count == 1, "snapshot list contains one deduplicated snapshot")
    check(SnapshotReason.manual.displayName == "Manual backup", "manual snapshot reason is user-readable")
    check(SnapshotReason.beforeEdit.displayName == "Before edit", "edit snapshot reason is user-readable")
    check(SnapshotReason.dailyOpen.displayName == "Daily app-open backup", "daily snapshot reason is user-readable")

    let snapshotsFolder = folder.appending(path: "snapshots")
    let badMetadataURL = snapshotsFolder.appending(path: "legacy.metadata.json")
    try "{ bad json".write(to: badMetadataURL, atomically: true, encoding: .utf8)
    let tolerantSnapshots = try store.list()
    check(
        tolerantSnapshots.map(\.metadata.timestamp) == [now],
        "snapshot list ignores unreadable legacy metadata"
    )

    let selectedRoot = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: selectedRoot) }
    let selectedSnapshotsFolder = selectedRoot.appending(path: "snapshots")
    try FileManager.default.createDirectory(at: selectedSnapshotsFolder, withIntermediateDirectories: true)
    let selectedFolderStore = SnapshotStore(folder: selectedSnapshotsFolder, codec: .init())
    let directTimestamp = now.addingTimeInterval(120)
    let directMetadata = SnapshotMetadata(
        timestamp: directTimestamp,
        schemaVersion: configuration.schemaVersion,
        tagsByShortcut: configuration.tagsByShortcut,
        reason: .manual
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try store.codec.encode(replacements).write(
        to: selectedSnapshotsFolder.appending(path: "direct.plist"),
        options: .atomic
    )
    try encoder.encode(directMetadata).write(
        to: selectedSnapshotsFolder.appending(path: "direct.metadata.json"),
        options: .atomic
    )
    let selectedFolderSnapshots = try selectedFolderStore.list()
    check(
        selectedFolderSnapshots.map(\.metadata.timestamp) == [directTimestamp],
        "snapshot list supports a selected snapshots folder"
    )

    let writtenSelectedFolderSnapshot = try selectedFolderStore.writeSnapshot(
        replacements: [.init(shortcut: ".b", phrase: "B")],
        configuration: ReplaceKitConfiguration(tagsByShortcut: [".b": ["personal"]]),
        reason: .beforeEdit,
        now: now.addingTimeInterval(180)
    )
    let writtenFolderPath = writtenSelectedFolderSnapshot?.plistURL
        .deletingLastPathComponent()
        .standardizedFileURL
        .path(percentEncoded: false)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let selectedFolderPath = selectedSnapshotsFolder
        .standardizedFileURL
        .path(percentEncoded: false)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    check(
        writtenFolderPath == selectedFolderPath,
        "snapshot writer does not create nested snapshots folder when selected folder is already snapshots"
    )

    let spacedRoot = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: spacedRoot) }
    let spacedSnapshotsFolder = spacedRoot
        .appending(path: "folder with spaces")
        .appending(path: "snapshots")
    try FileManager.default.createDirectory(at: spacedSnapshotsFolder, withIntermediateDirectories: true)
    let spacedTimestamp = now.addingTimeInterval(240)
    let spacedMetadata = SnapshotMetadata(
        timestamp: spacedTimestamp,
        schemaVersion: configuration.schemaVersion,
        tagsByShortcut: configuration.tagsByShortcut,
        reason: .manual
    )
    try store.codec.encode(replacements).write(
        to: spacedSnapshotsFolder.appending(path: "spaced.plist"),
        options: .atomic
    )
    try encoder.encode(spacedMetadata).write(
        to: spacedSnapshotsFolder.appending(path: "spaced.metadata.json"),
        options: .atomic
    )
    let spacedSnapshots = try SnapshotStore(folder: spacedSnapshotsFolder, codec: .init()).list()
    check(
        spacedSnapshots.map(\.metadata.timestamp) == [spacedTimestamp],
        "snapshot list supports backup folders with spaces"
    )
}

@MainActor
func testReplacementDiff() {
    let current = [
        TextReplacement(shortcut: ".keep", phrase: "old"),
        TextReplacement(shortcut: ".delete", phrase: "remove"),
    ]
    let proposed = [
        TextReplacement(shortcut: ".keep", phrase: "new"),
        TextReplacement(shortcut: ".add", phrase: "insert"),
    ]
    let diff = ReplacementDiff.compare(current: current, proposed: proposed)

    check(diff.added.map(\.shortcut) == [".add"], "diff reports additions")
    check(diff.deleted.map(\.shortcut) == [".delete"], "diff reports deletions")
    check(diff.edited.map(\.after.shortcut) == [".keep"], "diff reports edits")
    check(
        ReplacementDiff.basisChanged(
            preview: [TextReplacement(shortcut: ".a", phrase: "old")],
            observed: [TextReplacement(shortcut: ".a", phrase: "changed elsewhere")]
        ),
        "diff detects externally changed preview basis"
    )
}

@MainActor
func testRoutineEditPlanning() throws {
    let current = [TextReplacement(shortcut: ".a", phrase: "Alpha")]
    let configuration = ReplaceKitConfiguration(tagsByShortcut: [".a": ["old"]])

    let tagOnly = try RoutineEditPlanner.planUpdate(
        current: current,
        configuration: configuration,
        originalShortcut: ".a",
        shortcut: ".a",
        phrase: "Alpha",
        tags: ["new"]
    )
    check(!tagOnly.changesAppleRecords, "tag-only save skips System Settings writer")
    check(tagOnly.proposed == current, "tag-only save keeps Apple records unchanged")
    check(tagOnly.nextConfiguration.tagsByShortcut == [".a": ["new"]], "tag-only save updates local tags")

    let phraseEdit = try RoutineEditPlanner.planUpdate(
        current: current,
        configuration: configuration,
        originalShortcut: ".a",
        shortcut: ".a",
        phrase: "Edited",
        tags: ["new"]
    )
    check(phraseEdit.changesAppleRecords, "phrase save still uses System Settings writer")
}

@MainActor
func testMacPreferencesAndFallback() async throws {
    check(
        SystemSettingsWriterError.accessibilityPermissionMissing.localizedDescription ==
            "Accessibility permission is required to save through System Settings.",
        "System Settings writer errors are user-readable"
    )

    let reader = GlobalDefaultsTextReplacementReader(loadRecords: {
        [
            ["replace": ".ph", "with": 91471286, "on": 1],
            ["replace": "omw", "with": "On my way!", "on": 1],
        ]
    })
    let observed = try reader.fetchAll()
    check(
        observed == [
            TextReplacement(shortcut: ".ph", phrase: "91471286"),
            TextReplacement(shortcut: "omw", phrase: "On my way!"),
        ],
        "global defaults reader converts observed macOS records"
    )
    checkThrows("global defaults reader reports missing preference") {
        _ = try GlobalDefaultsTextReplacementReader(loadRecords: { nil }).fetchAll()
    }

    var directDomain: [String: Any] = [
        "UnrelatedPreference": true,
        "NSUserDictionaryReplacementItems": [
            ["replace": ".a", "with": "Alpha", "on": 1],
            ["replace": ".b", "with": "Bravo", "on": 1],
        ],
    ]
    let directWriter = GlobalDefaultsTextReplacementWriter(
        loadDomain: { directDomain },
        saveDomain: { directDomain = $0 }
    )
    let directReader = GlobalDefaultsTextReplacementReader(loadRecords: {
        directDomain["NSUserDictionaryReplacementItems"] as? [[String: Any]]
    })

    try await directWriter.add(.init(shortcut: ".c", phrase: "Charlie"))
    let addedDirectReplacements = try directReader.fetchAll()
    check(
        addedDirectReplacements.map(\.shortcut) == [".a", ".b", ".c"],
        "direct defaults writer adds a replacement without dropping existing records"
    )

    try await directWriter.update(
        originalShortcut: ".b",
        replacement: .init(shortcut: ".bb", phrase: "Bravo edited")
    )
    let updatedDirectReplacements = try directReader.fetchAll()
    check(
        updatedDirectReplacements.contains(.init(shortcut: ".bb", phrase: "Bravo edited")),
        "direct defaults writer updates and renames replacements"
    )

    try await directWriter.delete(shortcut: ".a")
    let deletedDirectReplacements = try directReader.fetchAll()
    let directRecords = directDomain["NSUserDictionaryReplacementItems"] as? [[String: Any]]
    check(
        deletedDirectReplacements.map(\.shortcut) == [".bb", ".c"],
        "direct defaults writer deletes replacements"
    )
    check(directDomain["UnrelatedPreference"] as? Bool == true, "direct defaults writer preserves unrelated global preferences")
    check(directRecords?.allSatisfy { ($0["on"] as? Int) == 1 } == true, "direct defaults writer writes enabled Apple records")

    let suite = "replacekit-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preference = BackupFolderPreference(defaults: defaults)
    let folder = temporaryFolder()
    preference.save(folder)
    check(preference.load() == folder, "backup folder preference persists selected path")

    let spacedFolder = URL(fileURLWithPath: "/tmp/ReplaceKit Space")
    preference.save(spacedFolder)
    check(
        defaults.string(forKey: "backupFolderPath") == "/tmp/ReplaceKit Space",
        "backup folder preference stores decoded file paths"
    )
    check(preference.load() == spacedFolder, "backup folder preference loads decoded file paths")

    defaults.set("/tmp/ReplaceKit%20Legacy", forKey: "backupFolderPath")
    check(
        preference.load() == URL(fileURLWithPath: "/tmp/ReplaceKit Legacy"),
        "backup folder preference loads legacy percent-encoded paths"
    )

    defer { try? FileManager.default.removeItem(at: folder) }
    let fallbackURL = try ManualImportService().export(
        [TextReplacement(shortcut: ".fallback", phrase: "Fallback")],
        to: folder
    )
    let fallbackData = try Data(contentsOf: fallbackURL)
    let decodedFallback = try TextReplacementPlistCodec().decode(fallbackData)
    check(
        decodedFallback == [
            TextReplacement(shortcut: ".fallback", phrase: "Fallback"),
        ],
        "manual fallback writes Apple-compatible plist"
    )
}

final class InMemoryGateway: TextReplacementReading, TextReplacementWriting, @unchecked Sendable {
    private var replacements: [TextReplacement]
    private let writeError: Error?
    private(set) var writeCount = 0

    init(_ replacements: [TextReplacement], writeError: Error? = nil) {
        self.replacements = replacements
        self.writeError = writeError
    }

    func fetchAll() throws -> [TextReplacement] {
        replacements.sorted { $0.shortcut < $1.shortcut }
    }

    func add(_ replacement: TextReplacement) async throws {
        writeCount += 1
        if let writeError { throw writeError }
        replacements.append(replacement)
    }

    func update(originalShortcut: String, replacement: TextReplacement) async throws {
        writeCount += 1
        if let writeError { throw writeError }
        replacements.removeAll { $0.shortcut == originalShortcut }
        replacements.append(replacement)
    }

    func delete(shortcut: String) async throws {
        writeCount += 1
        if let writeError { throw writeError }
        replacements.removeAll { $0.shortcut == shortcut }
    }
}

final class RecordingSnapshotWriter: SnapshotWriting, @unchecked Sendable {
    private let error: Error?
    private(set) var reasons: [SnapshotReason] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func write(
        replacements: [TextReplacement],
        configuration: ReplaceKitConfiguration,
        reason: SnapshotReason
    ) throws {
        if let error { throw error }
        reasons.append(reason)
    }
}

enum TestError: Error {
    case backupFolderUnavailable
    case writerFailure
}

@MainActor
func testApplyCoordinator() async throws {
    let gateway = InMemoryGateway([TextReplacement(shortcut: ".a", phrase: "old")])
    let snapshots = RecordingSnapshotWriter()
    let coordinator = ApplyCoordinator(reader: gateway, writer: gateway, snapshots: snapshots)
    let result = try await coordinator.apply(
        .update(originalShortcut: ".a", replacement: .init(shortcut: ".a", phrase: "new")),
        configuration: .init()
    )

    check(snapshots.reasons == [.beforeEdit], "routine edit snapshots before writing")
    check(result.observed == [TextReplacement(shortcut: ".a", phrase: "new")], "routine edit verifies observed state")

    let unprotectedGateway = InMemoryGateway([])
    let unavailableSnapshots = RecordingSnapshotWriter(error: TestError.backupFolderUnavailable)
    let unprotectedCoordinator = ApplyCoordinator(
        reader: unprotectedGateway,
        writer: unprotectedGateway,
        snapshots: unavailableSnapshots
    )
    _ = try await unprotectedCoordinator.apply(
        .add(.init(shortcut: ".once", phrase: "Once")),
        configuration: .init(),
        protection: .unprotectedOnce
    )
    check(unprotectedGateway.writeCount == 1, "explicit one-time unprotected edit bypasses snapshot failure")

    let protectedGateway = InMemoryGateway([])
    let protectedCoordinator = ApplyCoordinator(
        reader: protectedGateway,
        writer: protectedGateway,
        snapshots: unavailableSnapshots
    )
    do {
        _ = try await protectedCoordinator.apply(
            .add(.init(shortcut: ".blocked", phrase: "Blocked")),
            configuration: .init()
        )
        check(false, "missing backup protection blocks writes")
    } catch ApplyCoordinatorError.snapshotUnavailable {
        check(protectedGateway.writeCount == 0, "missing backup protection blocks writes")
    }

    let changedGateway = InMemoryGateway([TextReplacement(shortcut: ".a", phrase: "external")])
    let changedCoordinator = ApplyCoordinator(reader: changedGateway, writer: changedGateway, snapshots: snapshots)
    do {
        _ = try await changedCoordinator.apply(
            proposed: [TextReplacement(shortcut: ".a", phrase: "restored")],
            previewBasis: [TextReplacement(shortcut: ".a", phrase: "old")],
            configuration: .init()
        )
        check(false, "changed bulk preview basis requires a new confirmation")
    } catch ApplyCoordinatorError.changedBasis(let diff) {
        check(diff.edited.count == 1, "changed bulk preview basis requires a new confirmation")
    }

    let failingGateway = InMemoryGateway([], writeError: TestError.writerFailure)
    let failingCoordinator = ApplyCoordinator(reader: failingGateway, writer: failingGateway, snapshots: snapshots)
    do {
        _ = try await failingCoordinator.apply(
            .add(.init(shortcut: ".partial", phrase: "Partial")),
            configuration: .init()
        )
        check(false, "writer failure reports observed partial state")
    } catch ApplyCoordinatorError.partialResult(let observed, _) {
        check(observed.isEmpty, "writer failure reports observed partial state")
    }

    let accessibilityGateway = InMemoryGateway(
        [],
        writeError: SystemSettingsWriterError.accessibilityPermissionMissing
    )
    let accessibilityCoordinator = ApplyCoordinator(
        reader: accessibilityGateway,
        writer: accessibilityGateway,
        snapshots: snapshots
    )
    do {
        _ = try await accessibilityCoordinator.apply(
            .add(.init(shortcut: ".permission", phrase: "Permission")),
            configuration: .init()
        )
        check(false, "partial writer failures use user-readable messages")
    } catch ApplyCoordinatorError.partialResult(_, let message) {
        check(
            message == "Accessibility permission is required to save through System Settings.",
            "partial writer failures use user-readable messages"
        )
    }
}

@MainActor
func run() async throws {
    try testPlistCodec()
    try testConfigurationStore()
    try testSnapshotStore()
    testReplacementDiff()
    try testRoutineEditPlanning()
    try await testMacPreferencesAndFallback()
    try await testApplyCoordinator()
}

do {
    try await run()
} catch {
    failures += 1
    print("FAIL: unexpected error: \(error)")
}

if failures > 0 {
    exit(1)
}
