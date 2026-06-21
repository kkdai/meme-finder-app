import AppKit
import SwiftUI
import MemeFinder

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Exposed so the SwiftUI Settings scene (⌘,) can host the same real
    // SettingsView the menu-bar "設定…" item opens.
    let search: SearchViewModel
    let settings: SettingsViewModel
    let indexing: IndexingController
    private let indexURL: URL
    private let bookmark: FolderBookmark

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var hotKey: GlobalHotKey?
    private var reindexTask: Task<Void, Never>?

    override init() {
        let secrets = KeychainSecretStore()
        let bm = FolderBookmark()
        let service = LiveGeminiService(keyProvider: { secrets.apiKey() })
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let iURL = appSupport.appendingPathComponent("MemeFinder/index.json")
        let index = MemeIndex.load(from: iURL)
        self.search = SearchViewModel(service: service, clipboard: AppKitClipboardWriter(), index: index)
        self.settings = SettingsViewModel(secrets: secrets, bookmark: bm)
        self.indexing = IndexingController(service: service, indexURL: iURL)
        self.indexURL = iURL
        self.bookmark = bm
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "MemeFinder")
        item.button?.action = #selector(statusButtonClicked)
        item.button?.target = self
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.statusItem = item

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 680, height: 520)
        popover.contentViewController = NSHostingController(rootView: ContentView(vm: search))

        hotKey = GlobalHotKey(keyCode: HotKeyConstants.mKeyCode,
                              modifiers: carbonModifiers(command: true, control: true, option: false, shift: false)) { [weak self] in
            self?.togglePopover()
        }
        if hotKey?.isRegistered == false {
            NSLog("MemeFinder: ⌃⌘M global hotkey unavailable (already in use); use the menu-bar icon.")
        }
    }

    @objc private func statusButtonClicked() {
        guard let event = NSApp.currentEvent else { togglePopover(); return }
        if event.type == .rightMouseUp {
            // Pop the menu up directly rather than assigning statusItem.menu and
            // clearing it synchronously (which races AppKit's menu-tracking loop).
            if let button = statusItem?.button {
                NSMenu.popUpContextMenu(makeMenu(), with: event, for: button)
            }
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "搜尋…", action: #selector(openSearch), keyEquivalent: "").target = self
        menu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "重新索引", action: #selector(reindexNow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "結束 MemeFinder", action: #selector(quit), keyEquivalent: "q").target = self
        return menu
    }

    @objc private func openSearch() { togglePopover() }

    @objc func reindexNow() {
        reindexTask?.cancel()
        reindexTask = Task { @MainActor in
            guard let folder = bookmark.resolve() else { return }
            let existing = MemeIndex.load(from: indexURL)
            let newIndex = await indexing.reindex(folder: folder, existing: existing)
            search.updateIndex(newIndex)
        }
    }

    func cancelReindex() { reindexTask?.cancel() }

    @objc private func openSettings() {
        // Open the SwiftUI Settings scene — the same window ⌘, shows.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
