import AppKit
import ApplicationServices
import Darwin
import Foundation
import ReplaceKitCore
import ReplaceKitMac

guard AccessibilityTrust().isTrusted(prompt: true) else {
    fputs("Grant Accessibility permission, then run again.\n", stderr)
    exit(2)
}

func eventually(_ predicate: () throws -> Bool) async throws -> Bool {
    for _ in 0..<100 {
        if try predicate() {
            return true
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    return false
}

if CommandLine.arguments.contains("--smoke-write") {
    let shortcut = ".replacekit-\(UUID().uuidString.prefix(8))"
    let initial = TextReplacement(shortcut: shortcut, phrase: "ReplaceKit smoke test")
    let edited = TextReplacement(shortcut: shortcut, phrase: "ReplaceKit smoke test edited")
    let reader = GlobalDefaultsTextReplacementReader()
    let writer = SystemSettingsTextReplacementWriter()

    do {
        try await writer.add(initial)
        guard try await eventually({ try reader.fetchAll().contains(initial) }) else {
            throw ProbeError.postconditionFailed("add")
        }
        print("PASS: added \(shortcut)")

        try await writer.update(originalShortcut: shortcut, replacement: edited)
        guard try await eventually({ try reader.fetchAll().contains(edited) }) else {
            throw ProbeError.postconditionFailed("update")
        }
        print("PASS: updated \(shortcut)")

        try await writer.delete(shortcut: shortcut)
        guard try await eventually({ try !reader.fetchAll().contains(edited) }) else {
            throw ProbeError.postconditionFailed("delete")
        }
        print("PASS: deleted \(shortcut)")
        exit(0)
    } catch {
        if !CommandLine.arguments.contains("--keep-on-failure") {
            try? await writer.delete(shortcut: shortcut)
        }
        fputs("Smoke write failed for \(shortcut): \(error)\n", stderr)
        exit(4)
    }
}

if let deleteIndex = CommandLine.arguments.firstIndex(of: "--delete"),
   CommandLine.arguments.indices.contains(deleteIndex + 1)
{
    let shortcut = CommandLine.arguments[deleteIndex + 1]
    do {
        try await SystemSettingsTextReplacementWriter().delete(shortcut: shortcut)
        print("PASS: deleted \(shortcut)")
        exit(0)
    } catch {
        fputs("Delete failed for \(shortcut): \(error)\n", stderr)
        exit(5)
    }
}

guard let app = NSRunningApplication
    .runningApplications(withBundleIdentifier: "com.apple.systempreferences")
    .first
else {
    fputs("Open System Settings first.\n", stderr)
    exit(3)
}

func dump(_ element: AXElement, depth: Int = 0) {
    print(
        "\(String(repeating: "  ", count: depth))" +
            "\(element.role ?? "?") | \(element.subrole ?? "") | " +
            "\(element.title ?? "") | \(element.label ?? "") | \(element.value ?? "")"
    )
    for child in element.children {
        dump(child, depth: depth + 1)
    }
}

dump(AXElement(AXUIElementCreateApplication(app.processIdentifier)))

enum ProbeError: Error {
    case postconditionFailed(String)
}
