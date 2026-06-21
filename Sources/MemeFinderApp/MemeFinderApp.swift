import SwiftUI
import MemeFinder

@main
struct MemeFinderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        // ⌘, opens this scene; the menu-bar "設定…" opens the same one via
        // showSettingsWindow:. Both show the real SettingsView.
        Settings {
            SettingsView(
                vm: appDelegate.settings,
                indexing: appDelegate.indexing,
                onReindex: { appDelegate.reindexNow() },
                onCancel: { appDelegate.cancelReindex() }
            )
        }
    }
}
