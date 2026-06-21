import SwiftUI
import MemeFinder

@main
struct MemeFinderApp: App {
    @StateObject private var search: SearchViewModel
    @StateObject private var settings: SettingsViewModel
    @StateObject private var indexingController: IndexingController

    private let indexURL: URL
    private let bookmark: FolderBookmark

    init() {
        let secrets = KeychainSecretStore()
        let bm = FolderBookmark()
        let service = LiveGeminiService(apiKey: secrets.apiKey() ?? "")
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
            SettingsView(vm: settings) {
                let folder = bookmark.resolve()
                guard let folder else { return }
                Task { @MainActor in
                    let existing = MemeIndex.load(from: indexURL)
                    let newIndex = await indexingController.reindex(folder: folder, existing: existing)
                    search.updateIndex(newIndex)
                }
            }
        }
    }
}
