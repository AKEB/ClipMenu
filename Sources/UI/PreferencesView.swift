import SwiftUI

/// Root of the Settings scene — tabbed preferences window.
///
/// TODO: Phase 2 — build tab structure mirroring legacy Preferences.xib
///       (General, Menu, Actions, Shortcuts tabs from
///       legacy/Source/PrefsWindowController.{h,m}).
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
