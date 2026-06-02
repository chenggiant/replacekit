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
func run() throws {
    try testPlistCodec()
    try testConfigurationStore()
    try testSnapshotStore()
    testReplacementDiff()
}

do {
    try run()
} catch {
    failures += 1
    print("FAIL: unexpected error: \(error)")
}

if failures > 0 {
    exit(1)
}
