import SwiftUI

enum PreferencesTab: Hashable {
    case general
    case menu
    case snippets
    case actions
    case shortcuts
}

/// Root of the Settings scene — tabbed preferences window.
///
/// Mirrors the tab structure from `legacy/Source/PrefsWindowController.{h,m}`
/// (General, Menu, Actions, Shortcuts tabs).
struct PreferencesView: View {
    @State private var selection: PreferencesTab

    init(initialTab: PreferencesTab = .general) {
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            GeneralPrefsView()
                .tag(PreferencesTab.general)
                .tabItem { Label("General", systemImage: "gearshape") }

            MenuPrefsView()
                .tag(PreferencesTab.menu)
                .tabItem { Label("Menu", systemImage: "list.bullet") }

            SnippetsPrefsView()
                .tag(PreferencesTab.snippets)
                .tabItem { Label("Snippets", systemImage: "text.badge.plus") }

            ActionsPrefsView()
                .tag(PreferencesTab.actions)
                .tabItem { Label("Actions", systemImage: "bolt") }

            ShortcutsPrefsView()
                .tag(PreferencesTab.shortcuts)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(minWidth: 680, minHeight: 500)
    }
}

// MARK: - Preview

#Preview {
    PreferencesView()
        .environment(ClipMenuSettings())
        .environment(\.loginItemService, LoginItemService())
}
