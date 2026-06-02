# ReplaceKit Design

## Summary

ReplaceKit is a regular native macOS app for managing Apple's built-in Text
Replacements more conveniently. It improves daily editing, creates versioned
backups, adds lightweight tags, and previews bulk changes. It does not replace
Apple's storage or synchronization behavior.

Apple iCloud Drive remains the only sync path from macOS to iPhone and iPad.
ReplaceKit must not claim that a specific device has completed synchronization.

## Goals

- Provide a searchable editor for Apple's current replacement list.
- Apply routine add, edit, and delete actions immediately.
- Create timestamped, portable plist snapshots in a user-chosen folder.
- Add ReplaceKit-only tags without changing Apple's plist records.
- Show diffs before import, restore, or multi-row deletion.
- Preserve a manual Apple-compatible plist import fallback when automation
  cannot complete.

## Non-Goals

- An iOS app or custom cloud service.
- A replacement for Apple iCloud synchronization.
- Calls into private macOS frameworks.
- Menu bar mode.
- Smart variables, templates, clipboard expansion, or a general snippet engine.
- Built-in Git integration.
- Automatic history pruning.

## Platform Constraint

Apple documents iCloud synchronization for Text Replacements and a manual plist
backup and restore workflow in System Settings. Apple does not document a public
API for programmatically managing the replacement list. See
[Back up and share text replacements on Mac](https://support.apple.com/en-mt/guide/mac-help/mchl2a7bd795/mac).

ReplaceKit therefore uses macOS Accessibility permission to operate Apple's Text
Replacements settings panel. Apple's UI remains the writer of system records.
This approach is less brittle than private framework calls and more convenient
than requiring manual plist import for every routine edit.

## Architecture

ReplaceKit has five components:

### Editor

The primary window is an editor-first interface:

- Sidebar: `All`, tag filters, `History`, and `Settings`.
- Toolbar: search, `+ Add`, `Import`, and `Back Up Now`.
- Replacement table: shortcut, phrase preview, and tags.
- Inspector: edit the selected shortcut, phrase, and tags.

### Settings Co-pilot

The Settings Co-pilot drives Apple's Text Replacements settings panel through
macOS Accessibility automation. It applies routine changes and refreshes the
editor from macOS after each operation.

### Backup Engine

The Backup Engine writes timestamped snapshots into a user-chosen folder. It
creates a snapshot before every applied change and supports manual backup. A
setting, disabled by default, can create at most one daily snapshot when the app
is opened. The engine skips duplicate snapshots when replacement content and tag
metadata are unchanged.

### History

History lists snapshots and calculates additions, edits, deletions, and
conflicts. Restore always starts with a preview and confirmation.

### Manual Fallback

When Accessibility automation cannot complete reliably, ReplaceKit generates an
Apple-compatible plist and guides the user through Apple's supported drag-in
import workflow.

## Data Model

The selected backup folder has this structure:

```text
Text Replacements Backups/
  snapshots/
    2026-06-02T14-30-00Z.plist
    2026-06-02T14-30-00Z.metadata.json
  replacekit.json
```

Each plist is compatible with Apple's manual import workflow.

Each snapshot metadata file stores:

- Snapshot timestamp.
- ReplaceKit schema version.
- Tag mappings associated with that snapshot.
- Optional operation reason, such as `manual`, `before-edit`, or `daily-open`.

`replacekit.json` stores current tag mappings and app settings. It does not act
as a competing copy of Apple's replacement list.

Tags are ReplaceKit-only metadata. They never alter Apple's plist records and do
not appear on iOS. Tag mappings use the shortcut as the replacement identity.
ReplaceKit requires shortcuts to be unique. Renaming a shortcut through
ReplaceKit migrates its tags to the new shortcut. If replacements changed
outside ReplaceKit cause an identity conflict, the editor shows the affected
rows as untagged until the user resolves the conflict.

## Apply Rules

### Routine Operations

Routine operations are adding one replacement, editing one replacement, or
deleting one replacement.

For each routine operation:

1. Refresh the current macOS list.
2. Create a pre-change snapshot.
3. Apply the operation through the Settings Co-pilot.
4. Refresh the current macOS list again.
5. Confirm success or show the observed partial result.

### Guarded Operations

Guarded operations are plist import, snapshot restore, or deletion of multiple
rows.

For each guarded operation:

1. Refresh the current macOS list.
2. Calculate and display a diff with additions, edits, deletions, and conflicts.
3. Require explicit confirmation.
4. Create a pre-change snapshot.
5. Apply the confirmed changes through the Settings Co-pilot when possible.
6. Refresh from macOS and report the result.

If the current macOS list changed between preview and apply, recalculate the diff
and require confirmation again.

## Failure Handling

### Missing Accessibility Permission

Explain why Accessibility permission is needed and provide an action to open the
appropriate macOS permission page. No automated write is attempted without
permission.

### Automation Failure

Do not silently continue after a failure. Refresh the current macOS list, show
which operations completed, and offer a generated plist for Apple's manual
drag-in import workflow.

### Unavailable Backup Folder

Block edits until the user chooses a writable folder or explicitly confirms a
one-time unprotected edit. Make the lack of a pre-change snapshot visible.

### External Changes

Refresh from macOS before apply. If the observed list differs from the basis of
a pending bulk preview, show the updated diff and require confirmation again.

## Testing

### Automated Tests

- Parse and generate Apple-compatible plist files.
- Preserve Unicode, multiline phrases, punctuation, and emoji.
- Store and reload tags without leaking them into Apple records.
- Calculate additions, edits, deletions, and conflicts correctly.
- Skip identical snapshots.
- Detect a changed basis before guarded apply.
- Block protected edits when the selected backup folder is unavailable.

### macOS Integration Tests

- Apply routine add, edit, and delete operations through the current macOS
  Settings panel.
- Verify missing Accessibility permission handling.
- Force an automation failure and verify partial-result reporting.
- Generate a fallback plist and import it manually through Apple's documented
  drag-in workflow.

### Manual End-to-End Check

Add a replacement through ReplaceKit on Mac and confirm that it appears on an
iPhone through Apple's iCloud synchronization.

## Version-One Success Criteria

- The editor loads the current macOS Text Replacements list.
- A user can search and filter the list by tag.
- A user can add, edit, and delete one replacement with an automatic pre-change
  snapshot.
- A user can import or restore only after reviewing a diff.
- A user can recover through a portable plist when automation fails.
- A user can choose an iCloud Drive folder, Git working tree, or ordinary local
  folder for snapshots.
- Tags persist independently without affecting Apple's records.
