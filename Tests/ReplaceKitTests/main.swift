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
        createDailySnapshotOnOpen: true
    )

    try store.save(configuration)
    let loaded = try store.load()
    check(loaded == configuration, "configuration round trips tags and settings")
    check(
        configuration.renamingShortcut(from: ".hello", to: ".hi").tagsByShortcut == [".hi": ["work", "greeting"]],
        "renaming shortcut migrates tags"
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
func testMacPreferencesAndFallback() throws {
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

    let suite = "replacekit-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preference = BackupFolderPreference(defaults: defaults)
    let folder = temporaryFolder()
    preference.save(folder)
    check(preference.load() == folder, "backup folder preference persists selected path")

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
}

@MainActor
func run() async throws {
    try testPlistCodec()
    try testConfigurationStore()
    try testSnapshotStore()
    testReplacementDiff()
    try testMacPreferencesAndFallback()
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
