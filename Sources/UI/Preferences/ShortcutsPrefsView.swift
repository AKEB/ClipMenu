import SwiftUI

/// Shortcuts tab in the Preferences window.
///
/// Phase 3 will replace the placeholder text with KeyboardShortcuts.Recorder
/// controls once the HotkeyService is wired in.
/// Reference: `legacy/English.lproj/Preferences.strings` (key "Shortcuts").
struct ShortcutsPrefsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Clipboard menu") {
                    Text("Cmd+Shift+V")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("History menu") {
                    Text("Cmd+Ctrl+V")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Snippets menu") {
                    Text("Cmd+Shift+B")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Shortcut customisation is available in Phase 3.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    ShortcutsPrefsView()
        .frame(width: 520)
}
