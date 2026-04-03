import SwiftUI

/// Root of the Settings scene — tabbed preferences window.
///
/// Mirrors the tab structure from `legacy/Source/PrefsWindowController.{h,m}`
/// (General, Menu, Actions, Shortcuts tabs).
struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPrefsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            MenuPrefsView()
                .tabItem { Label("Menu", systemImage: "list.bullet") }

            ActionsPrefsView()
                .tabItem { Label("Actions", systemImage: "bolt") }

            ShortcutsPrefsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

// MARK: - Preview

#Preview {
    PreferencesView()
        .environment(ClipMenuSettings())
        .environment(\.loginItemService, LoginItemService())
}
