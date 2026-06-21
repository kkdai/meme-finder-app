import SwiftUI
import MemeFinder

@main
struct MemeFinderApp: App {
    @StateObject private var search: SearchViewModel
    @StateObject private var settings: SettingsViewModel

    init() {
        let secrets = KeychainSecretStore()
        let bookmark = FolderBookmark()
        let service = LiveGeminiService(apiKey: secrets.apiKey() ?? "")
        let indexURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MemeFinder/index.json")
        let index = MemeIndex.load(from: indexURL)
        _search = StateObject(wrappedValue: SearchViewModel(service: service,
                                                            clipboard: AppKitClipboardWriter(),
                                                            index: index))
        _settings = StateObject(wrappedValue: SettingsViewModel(secrets: secrets, bookmark: bookmark))
    }

    var body: some Scene {
        WindowGroup { ContentView(vm: search) }
        Settings { SettingsView(vm: settings) }
    }
}
