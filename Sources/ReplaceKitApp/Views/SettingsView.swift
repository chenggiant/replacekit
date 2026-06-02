import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Backups") {
                LabeledContent("Folder") {
                    Text(model.backupFolder?.path() ?? "Not selected")
                        .foregroundStyle(.secondary)
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

            Section("Accessibility") {
                LabeledContent("Permission") {
                    Text(model.accessibilityTrusted ? "Granted" : "Required for edits")
                        .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                }
                Button("Request Accessibility Permission") {
                    model.requestAccessibilityPermission()
                }
                Button("Open Keyboard Settings") {
                    model.openKeyboardSettings()
                }
            }

            if model.pendingProtectedApply != nil {
                Section("Unprotected Edit") {
                    Text("ReplaceKit could not write a pre-change snapshot. Choose a writable folder or explicitly apply once without backup protection.")
                    Button("Apply Once Without Snapshot") {
                        Task { await model.applyPendingWithoutSnapshot() }
                    }
                }
            }

            if let fallback = model.fallbackPlistURL {
                Section("Manual Fallback") {
                    Text("Automation could not finish. Drag this plist into Apple's Text Replacements list in System Settings.")
                    Text(fallback.path())
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button("Reveal Plist In Finder") {
                        model.revealFallbackPlist()
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Settings")
    }
}
