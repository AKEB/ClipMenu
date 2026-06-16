import SwiftUI
import SwiftData

@main
struct ClipMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    private let runtime = AppRuntime.shared
    private let isPasteUITestMode = ProcessInfo.processInfo.environment["CLIPMENU_UI_TEST_MODE"] == "1"

    init() {
        let schema = Schema([
            ClipEntry.self,
            SnippetFolder.self,
            Snippet.self,
            ActionNode.self,
        ])

        let configuration: ModelConfiguration
        if isPasteUITestMode {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
        } else {
            let storeURL = (try? SwiftDataStoreLocation.storeURL()) ?? URL(fileURLWithPath: "/tmp/ClipMenu.store")
            SwiftDataStoreLocation.migrateLegacyStoreIfNeeded(to: storeURL)
            configuration = ModelConfiguration(
                schema: schema,
                url: storeURL
            )
        }

        modelContainer = try! ModelContainer(for: schema, configurations: [configuration])
        runtime.modelContainer = modelContainer
    }

    var body: some Scene {
        Settings {
            PreferencesView()
                .modelContainer(modelContainer)
                .environment(runtime.settings)
                .environment(\.loginItemService, runtime.loginItemService)
        }
        .modelContainer(modelContainer)
    }
}
