# ReplaceKit Priority UX Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the clarity, space usage, and confidence of ReplaceKit's existing editing, settings, history, and diff workflows.

**Architecture:** Keep write behavior in the existing model and writers. Add only the small pieces of state needed to describe a pending bulk edit, localize writer errors at their source, and make SwiftUI views reflect current model state more clearly.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Package Manager

---

### Task 1: User-Readable Writer Errors

**Files:**
- Modify: `Tests/ReplaceKitTests/main.swift`
- Modify: `Sources/ReplaceKitMac/Accessibility/SystemSettingsTextReplacementWriter.swift`
- Modify: `Sources/ReplaceKitCore/Apply/ApplyCoordinator.swift`

- [ ] Add a failing test that expects Accessibility writer errors to produce a user-readable message instead of an enum case name.
- [ ] Run `swift run ReplaceKitTests` and verify the new assertion fails.
- [ ] Make `SystemSettingsWriterError` conform to `LocalizedError` and have `ApplyCoordinator` use `localizedDescription`.
- [ ] Run `swift run ReplaceKitTests` and verify the test passes.

### Task 2: Bulk Preview Context

**Files:**
- Modify: `Sources/ReplaceKitApp/AppModel.swift`
- Modify: `Sources/ReplaceKitApp/Views/DiffPreviewView.swift`

- [ ] Add an app-level bulk edit source enum for import, restore, and multi-row delete previews.
- [ ] Pass the source through `prepareBulk` and store it in `PendingBulkEdit`.
- [ ] Use the source to render a specific title, description, and confirmation action.
- [ ] Add count summaries and explicit before/after labels in the diff view.

### Task 3: Editor Layout And Save Feedback

**Files:**
- Modify: `Sources/ReplaceKitApp/Views/EditorView.swift`

- [ ] Make the editor split view fill the detail column.
- [ ] Give shortcuts, phrases, and tags distinct visual hierarchy.
- [ ] Add empty list and empty search states.
- [ ] Make Add prominent, group import and backup, and keep Delete contextual.
- [ ] Add a selected-replacement header, ReplaceKit-only tag guidance, destination-aware Save text, and busy-state progress.

### Task 4: Settings And History Clarity

**Files:**
- Modify: `Sources/ReplaceKitApp/Views/SettingsView.swift`
- Modify: `Sources/ReplaceKitApp/Views/HistoryView.swift`

- [ ] Make both screens fill the detail column and align content to the top.
- [ ] Combine write mode and Accessibility controls into a "Saving & Sync" section.
- [ ] Mark the iCloud path as recommended and the experimental path as local-only.
- [ ] Rename quiet apply to describe reduced disruption without implying invisibility.
- [ ] Improve backup path rendering and History empty-state copy.
- [ ] Make snapshot date and reason primary and filename secondary.

### Task 5: Verification

**Files:**
- Modify: none

- [ ] Run `swift run ReplaceKitTests`.
- [ ] Run `swift build`.
- [ ] Run `Scripts/package-app.sh`.
- [ ] Verify `outputs/ReplaceKit.app` with `codesign --verify --deep --strict`.
- [ ] Open the packaged app and visually inspect the changed screens.
