import SwiftUI
import MemeFinder

@main
struct MemeFinderApp: App {
    @StateObject private var search: SearchViewModel
    @StateObject private var settings: SettingsViewModel
    @StateObject private var indexingController: IndexingController
    @State private var reindexTask: Task<Void, Never>?

    private let indexURL: URL
    private let bookmark: FolderBookmark

    init() {
        let secrets = KeychainSecretStore()
        let bm = FolderBookmark()
        let service = LiveGeminiService(keyProvider: { secrets.apiKey() })
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let iURL = appSupport.appendingPathComponent("MemeFinder/index.json")
        let index = MemeIndex.load(from: iURL)
        _search = StateObject(wrappedValue: SearchViewModel(service: service,
                                                            clipboard: AppKitClipboardWriter(),
                                                            index: index))
        _settings = StateObject(wrappedValue: SettingsViewModel(secrets: secrets, bookmark: bm))
        _indexingController = StateObject(wrappedValue: IndexingController(service: service, indexURL: iURL))
        self.indexURL = iURL
        self.bookmark = bm
    }

    var body: some Scene {
        WindowGroup { ContentView(vm: search) }
        Settings {
            SettingsView(
                vm: settings,
                indexing: indexingController,
                onReindex: {
                    reindexTask?.cancel()
                    reindexTask = Task { @MainActor in
                        guard let folder = bookmark.resolve() else { return }
                        let existing = MemeIndex.load(from: indexURL)
                        let newIndex = await indexingController.reindex(folder: folder, existing: existing)
                        search.updateIndex(newIndex)
                    }
                },
                onCancel: { reindexTask?.cancel() }
            )
        }
    }
}
