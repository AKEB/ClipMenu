import SwiftUI

/// Actions tab in the Preferences window.
///
/// Covers: enable toggle, modifier-click behaviours, invoke-immediately.
/// Reference: `legacy/Source/PrefsWindowController.{h,m}` Actions tab.
struct ActionsPrefsView: View {

    @Environment(ClipMenuSettings.self) private var settings

    var body: some View {
        @Bindable var s = settings
        Form {
            Section("Action System") {
                Toggle("Enable actions", isOn: $s.enableAction)
                Toggle("Invoke action immediately when only one is available",
                       isOn: $s.invokeActionImmediately)
                    .disabled(!settings.enableAction)
            }

            Section("Modified-Click Behaviour") {
                clickBehaviorPicker("Control+click", binding: $s.controlClickBehavior)
                clickBehaviorPicker("Shift+click",   binding: $s.shiftClickBehavior)
                clickBehaviorPicker("Option+click",  binding: $s.optionClickBehavior)
                clickBehaviorPicker("Command+click", binding: $s.commandClickBehavior)
            }
            .disabled(!settings.enableAction)
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Helpers

    /// Picker that maps between the stored behavior string and a display label.
    /// Legacy values: "" (no-op), "popUpActionMenu" (show action menu).
    @ViewBuilder
    private func clickBehaviorPicker(_ label: String, binding: Binding<String>) -> some View {
        Picker(label, selection: binding) {
            Text("No action").tag("")
            Text("Show action menu").tag("popUpActionMenu")
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Preview

#Preview {
    ActionsPrefsView()
        .environment(ClipMenuSettings())
        .frame(width: 520)
}
