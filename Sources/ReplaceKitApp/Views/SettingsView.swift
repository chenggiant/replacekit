import Foundation
import ReplaceKitCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Backups") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(backupFolderPath)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(fullBackupFolderPath)
                }

                Button("Choose Folder") {
                    model.chooseBackupFolder()
                }

                Toggle(
                    "Create at most one daily snapshot when app opens",
                    isOn: $model.configuration.createDailySnapshotOnOpen
                )
                .onChange(of: model.configuration.createDailySnapshotOnOpen) {
                    model.saveConfiguration()
                }
            }

            Section("Saving & Sync") {
                Picker("Save replacements using", selection: $model.configuration.writeMode) {
                    ForEach(ReplacementWriteMode.allCases, id: \.self) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                    }
                }
                .onChange(of: model.configuration.writeMode) {
                    model.saveConfiguration()
                }

                switch model.configuration.writeMode {
                case .systemSettings:
                    Text("Uses Apple's Text Replacements interface so edits follow the normal Mac and iCloud sync path.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("Accessibility") {
                        Text(model.accessibilityTrusted ? "Granted" : "Required for saving")
                            .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                    }

                    Toggle("Reduce System Settings disruption", isOn: Binding(
                        get: {
                            model.configuration.systemSettingsApplyMode == .quiet
                        },
                        set: { isQuiet in
                            model.configuration.systemSettingsApplyMode = isQuiet ? .quiet : .standard
                            model.saveConfiguration()
                        }
                    ))
                    Text("Moves Settings to the edge, applies the change, hides it, and restores your previous app. System Settings may still be briefly visible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Request Accessibility Permission") {
                            model.requestAccessibilityPermission()
                        }
                        Button("Open Keyboard Settings") {
                            model.openKeyboardSettings()
                        }
                    }
                case .directDefaultsExperimental:
                    LabeledContent("Sync") {
                        Text("Local only")
                            .foregroundStyle(.orange)
                    }
                    Text("Writes an undocumented Mac preference directly. No Settings window opens and Accessibility is not needed, but these changes do not reliably publish to iCloud.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if model.pendingProtectedApply != nil {
                Section("Unprotected Edit") {
                    Text("ReplaceKit could not write a pre-change snapshot. Choose a writable folder or explicitly apply once without backup protection.")
                    Button("Apply Once Without Snapshot") {
                        Task { await model.applyPendingWithoutSnapshot() }
                    }
                    .disabled(model.isBusy)
                }
            }

            if let fallback = model.fallbackPlistURL {
                Section("Manual Fallback") {
                    Text("Automation could not finish. Drag this plist into Apple's Text Replacements list in System Settings.")
                    Text(fallback.path(percentEncoded: false))
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Button("Reveal Plist In Finder") {
                        model.revealFallbackPlist()
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Settings")
    }

    private var backupFolderPath: String {
        (fullBackupFolderPath as NSString).abbreviatingWithTildeInPath
    }

    private var fullBackupFolderPath: String {
        model.backupFolder?.path(percentEncoded: false) ?? "Not selected"
    }
}
