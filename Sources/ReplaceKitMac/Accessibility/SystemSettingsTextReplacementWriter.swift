import AppKit
import ApplicationServices
import Foundation
import ReplaceKitCore

public enum SystemSettingsWriterError: Error {
    case accessibilityPermissionMissing
    case settingsUnavailable
    case textReplacementsSheetUnavailable
    case unexpectedSheetShape(String)
    case replacementNotFound(String)
}

public actor SystemSettingsTextReplacementWriter: TextReplacementWriting {
    private let resolver = SystemSettingsSheetResolver()

    public init() {}

    public func add(_ replacement: TextReplacement) async throws {
        let sheet = try await resolver.resolveTextReplacementsSheet()
        try MacOS26TextReplacementSheet(sheet: sheet).add(
            shortcut: replacement.shortcut,
            phrase: replacement.phrase
        )
    }

    public func update(originalShortcut: String, replacement: TextReplacement) async throws {
        try await delete(shortcut: originalShortcut)
        try await add(replacement)
    }

    public func delete(shortcut: String) async throws {
        let sheet = try await resolver.resolveTextReplacementsSheet()
        try MacOS26TextReplacementSheet(sheet: sheet).delete(shortcut: shortcut)
    }

}

private struct SystemSettingsSheetResolver: Sendable {
    private let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    func resolveTextReplacementsSheet() async throws -> AXElement {
        guard AccessibilityTrust().isTrusted(prompt: true) else {
            throw SystemSettingsWriterError.accessibilityPermissionMissing
        }

        _ = await MainActor.run {
            NSWorkspace.shared.open(settingsURL)
        }

        let clock = ContinuousClock()
        let launchDeadline = clock.now.advanced(by: .seconds(5))
        var attemptedOpen = false
        while clock.now < launchDeadline {
            if let root = await settingsRoot() {
                if let sheet = uniqueTextReplacementsSheet(in: root) {
                    return sheet
                }
                if !attemptedOpen {
                    attemptedOpen = true
                    try? openTextReplacementsSheet(in: root)
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw SystemSettingsWriterError.textReplacementsSheetUnavailable
    }

    @MainActor
    private func settingsRoot() -> AXElement? {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.systempreferences")
            .first
        else {
            return nil
        }
        app.activate()
        return AXElement(AXUIElementCreateApplication(app.processIdentifier))
    }

    private func uniqueTextReplacementsSheet(in root: AXElement) -> AXElement? {
        let sheets = root.descendants.filter {
            $0.role == (kAXSheetRole as String) &&
                $0.descendants.filter { $0.role == (kAXOutlineRole as String) }.count == 1
        }
        return sheets.count == 1 ? sheets[0] : nil
    }

    private func openTextReplacementsSheet(in root: AXElement) throws {
        let buttons = root.descendants.filter {
            $0.role == (kAXButtonRole as String) &&
                ($0.label?.hasPrefix("Text Replacements") == true ||
                    $0.title?.hasPrefix("Text Replacements") == true)
        }
        if buttons.count == 1 {
            try buttons[0].press()
            return
        }

        let labels = root.descendants.filter {
            $0.role == (kAXStaticTextRole as String) &&
                ($0.value == "Text replacements" || $0.title == "Text replacements")
        }
        guard labels.count == 1 else {
            throw SystemSettingsWriterError.textReplacementsSheetUnavailable
        }
        try labels[0].clickAtCenter()
    }
}

private struct MacOS26TextReplacementSheet {
    private struct Row {
        let element: AXElement
        let shortcut: AXElement
        let phrase: AXElement
    }

    private let sheet: AXElement
    private let outline: AXElement

    init(sheet: AXElement) throws {
        let outlines = sheet.descendants.filter { $0.role == (kAXOutlineRole as String) }
        guard outlines.count == 1 else {
            throw SystemSettingsWriterError.unexpectedSheetShape("expected one replacement outline")
        }
        self.sheet = sheet
        self.outline = outlines[0]
    }

    func add(shortcut: String, phrase: String) throws {
        let controls = try controls()
        try controls.add.press()
        guard let addSheet = waitForNestedAddSheet() else {
            throw SystemSettingsWriterError.unexpectedSheetShape("expected nested add sheet")
        }
        let fields = addFields(in: addSheet)
        let addButtons = buttons(in: addSheet, named: "Add")
        guard fields.count == 2, addButtons.count == 1 else {
            throw SystemSettingsWriterError.unexpectedSheetShape("expected two add fields and one nested add button")
        }
        try replaceValue(shortcut, in: fields[0])
        try replaceValue(phrase, in: fields[1])
        guard waitUntilEnabled(addButtons[0]) else {
            throw SystemSettingsWriterError.unexpectedSheetShape("nested add button remains disabled after setting fields")
        }
        try addButtons[0].press()
        waitForNestedAddSheetToClose()
        guard waitForRow(shortcut: shortcut) else {
            throw SystemSettingsWriterError.unexpectedSheetShape("added shortcut did not appear in primary table")
        }
        try controls.done.press()
    }

    func delete(shortcut: String) throws {
        let row = try requiredRow(shortcut: shortcut)
        try row.element.select()
        let controls = try controls()
        guard controls.remove.isEnabled else {
            throw SystemSettingsWriterError.unexpectedSheetShape("remove button is disabled after row selection")
        }
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
        try outline.children
            .filter { $0.role == (kAXRowRole as String) }
            .map { element in
                let cells = element.children.filter { $0.role == (kAXCellRole as String) }
                let fields = cells.compactMap { cell -> AXElement? in
                    let values = cell.descendants.filter { $0.role == (kAXTextFieldRole as String) }
                    return values.count == 1 ? values[0] : nil
                }
                guard cells.count == 2, fields.count == 2 else {
                    throw SystemSettingsWriterError.unexpectedSheetShape("expected two text fields per replacement row")
                }
                return Row(element: element, shortcut: fields[0], phrase: fields[1])
            }
    }

    private func addFields(in addSheet: AXElement) -> [AXElement] {
        for group in addSheet.descendants where group.role == (kAXGroupRole as String) {
            let labels = group.children
                .filter { $0.role == (kAXStaticTextRole as String) }
                .compactMap(\.value)
            let fields = group.children.filter { $0.role == (kAXTextFieldRole as String) }
            if labels == ["Replace", "With"], fields.count == 2 {
                return fields
            }
        }
        return []
    }

    private func controls() throws -> (add: AXElement, remove: AXElement, done: AXElement) {
        let add = buttons(in: sheet, named: "Add")
        let remove = buttons(in: sheet, named: "Remove")
        let done = buttons(in: sheet, named: "Done")
        guard add.count == 1, remove.count == 1, done.count == 1 else {
            throw SystemSettingsWriterError.unexpectedSheetShape(
                "expected one primary Add, Remove, and Done button; found add=\(add.count), remove=\(remove.count), done=\(done.count)"
            )
        }
        return (add: add[0], remove: remove[0], done: done[0])
    }

    private func waitForNestedAddSheet() -> AXElement? {
        for _ in 0..<20 {
            let nestedSheets = sheet.children.filter { $0.role == (kAXSheetRole as String) }
            if nestedSheets.count == 1 {
                return nestedSheets[0]
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    private func waitForNestedAddSheetToClose() {
        for _ in 0..<20 {
            if sheet.children.allSatisfy({ $0.role != (kAXSheetRole as String) }) {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func waitUntilEnabled(_ element: AXElement) -> Bool {
        for _ in 0..<20 {
            if element.isEnabled {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private func replaceValue(_ value: String, in field: AXElement) throws {
        try field.clickAtCenter()
        try field.focus()
        try field.setStringValue(value)
        try AXElement.nudgeTextValidation()
        try AXElement.pressTab()
    }

    private func waitForRow(shortcut: String) -> Bool {
        for _ in 0..<20 {
            if (try? rows().contains(where: { $0.shortcut.value == shortcut })) == true {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private func buttons(in element: AXElement, named name: String) -> [AXElement] {
        element.descendants.filter {
            $0.role == (kAXButtonRole as String) && ($0.label == name || $0.title == name)
        }
    }
}
