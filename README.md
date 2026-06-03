# ReplaceKit

ReplaceKit is a native macOS utility for Apple's built-in Text Replacements. It
keeps Apple's storage and iCloud sync path in charge while adding a searchable
editor, lightweight tags, versioned plist backups, guarded import and restore,
and a manual fallback when Settings automation cannot complete.

## Build

This project builds with Apple's Command Line Tools:

```bash
swift run ReplaceKitTests
swift build
Scripts/package-app.sh
open outputs/ReplaceKit.app
```

`Scripts/package-app.sh` creates a Finder-launchable app at
`outputs/ReplaceKit.app`. If a local `ReplaceKit Local Code Signing` identity
exists, the script uses it so macOS Accessibility approval survives rebuilds.
Otherwise it falls back to ad-hoc signing.

## First Launch

1. Open ReplaceKit.
2. Choose a writable backup folder. This can be an ordinary local folder, an
   iCloud Drive folder, or a folder inside an existing Git working tree.
3. Open Settings in ReplaceKit and grant Accessibility permission when prompted.

Accessibility permission is required only so ReplaceKit can operate Apple's Text
Replacements panel in System Settings. ReplaceKit does not call private
frameworks and does not write the undocumented global preference directly.

## Backup Folder

ReplaceKit stores ordinary files:

```text
Text Replacements Backups/
  snapshots/
    2026-06-02T14-30-00Z.plist
    2026-06-02T14-30-00Z.metadata.json
  replacekit.json
```

The plist files contain Apple replacement records. JSON files contain ReplaceKit
metadata such as tags and backup reasons. Tags remain ReplaceKit-only and do not
appear on iPhone or iPad.

## Manual Fallback

If Settings automation cannot finish, ReplaceKit generates
`property list.plist` and reveals it in Finder. Open System Settings, go to
Keyboard > Text Input > Text Replacements, then drag the plist into the list.

Apple documents this plist backup and restore workflow in
[Back up and share text replacements on Mac](https://support.apple.com/en-mt/guide/mac-help/mchl2a7bd795/mac).

## Compatibility Boundary

Apple does not publish an API for managing Text Replacements. ReplaceKit reads
the observed `NSUserDictionaryReplacementItems` global preference to refresh its
editor, but all system writes go through Apple's Settings UI. A future macOS
release may require an adapter update if Apple changes that UI or preference.

## Diagnostic Probe

To inspect the current System Settings Accessibility tree:

```bash
swift run ReplaceKitAXProbe
```

To run a disposable add, update, and delete smoke test through System Settings:

```bash
swift run ReplaceKitAXProbe --smoke-write
```
