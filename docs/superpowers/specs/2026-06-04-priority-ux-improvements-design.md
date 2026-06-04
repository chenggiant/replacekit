# ReplaceKit Priority UX Improvements Design

## Scope

This pass addresses the existing-feature UX feedback in priority order. It does
not add new replacement capabilities or change how ReplaceKit writes Apple's
Text Replacements.

## Design

### Window Layout

Editor, Settings, and History content fill the available detail-column height
and align to the top. Lists and tables receive the flexible space instead of
leaving a large unused area above the content.

### Replacement Editing

The replacement table makes shortcuts the strongest visual anchor, phrases
secondary, and ReplaceKit tags compact tertiary metadata. Empty search results
show a specific message.

The toolbar keeps Add prominent, groups import and backup actions, and keeps
deletion contextual. The inspector identifies the selected replacement, labels
tags as ReplaceKit-only metadata, separates Delete from Save, and changes the
Save label based on the write destination. While a write is active, controls
show progress and disable conflicting actions.

### Saving And Sync Settings

Settings groups write mode, Accessibility status, reduced-disruption behavior,
and related actions under one "Saving & Sync" section. The System Settings and
iCloud path is clearly recommended. The experimental direct-defaults path is
clearly local-only. Backup paths are readable without dominating the form.

### History And Diff Review

History empty-state copy reflects whether a backup folder is already selected.
Snapshot date and reason are primary; the filename is secondary.

Bulk-change previews identify whether the user is reviewing an import, restore,
or multi-row delete. They show added, edited, and deleted counts before the
detailed list, and edited rows explicitly label before and after values.

### Errors

Writer failures use user-readable descriptions so internal enum case names such
as `accessibilityPermissionMissing` are not shown in alerts.

## Verification

- Automated tests cover user-readable writer errors and any new core diff
  behavior.
- `swift run ReplaceKitTests` and `swift build` pass.
- The packaged app is opened and visually checked on Editor, Settings, History,
  add sheet, and diff preview paths where practical.
