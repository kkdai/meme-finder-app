# Menu Bar + Global Hotkey Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn MemeFinder into a Dock-less menu-bar app: a status-bar icon and a fixed global hotkey (⌃⌘M) toggle a popover containing the existing search UI; settings/reindex move into the status menu.

**Architecture:** Add pure `carbonModifiers`/`HotKeyConstants` helpers (tested) and a thin `GlobalHotKey` Carbon wrapper in the library. Replace the SwiftUI `WindowGroup` app entry with an `NSApplicationDelegateAdaptor` whose `AppDelegate` owns all view models, an `NSStatusItem` + `NSPopover` hosting `ContentView`, a settings `NSWindow`, and the `GlobalHotKey`. `build-app.sh` sets `LSUIElement` to hide the Dock icon.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSStatusItem`, `NSPopover`, `NSHostingController`), Carbon (`RegisterEventHotKey`), Swift Testing. Library target `MemeFinder`; executable `MemeFinderApp`.

## Global Constraints

- `MemeFinder` is a library target (view models import Combine); `MemeFinderApp` is the executable (SwiftUI/AppKit).
- Test framework: Swift Testing (`import Testing`, `@Test`, `#expect`); run `swift test`.
- Global hotkey is FIXED ⌃⌘M: keyCode 46 (`kVK_ANSI_M`), modifiers = command + control. No user customization (YAGNI).
- Carbon `RegisterEventHotKey` needs NO Accessibility permission; registration failure (key taken) must NOT crash — icon still works.
- App is non-sandboxed; Dock hidden via `LSUIElement = true` in Info.plist.
- Reuse existing view models unchanged: `SearchViewModel`, `SettingsViewModel`, `IndexingController`, `LiveGeminiService(keyProvider:)`, `KeychainSecretStore`, `FolderBookmark`, `AppKitClipboardWriter`, `MemeIndex`. Index path = Application Support `MemeFinder/index.json`.
- Existing 43 tests must not regress.
- Output pristine (no warnings).
- Commit after every task with a `feat:`/`test:` prefixed message.

---

## File Structure

```
Sources/MemeFinder/
  Logic/
    HotKeyModifiers.swift     # NEW: carbonModifiers() + HotKeyConstants — pure, tested
  Services/
    GlobalHotKey.swift        # NEW: Carbon RegisterEventHotKey wrapper (build-verified)
Sources/MemeFinderApp/
  AppDelegate.swift           # NEW: NSStatusItem + NSPopover + settings window + hotkey + wiring
  MemeFinderApp.swift         # MODIFY: adaptor + empty Settings scene (no WindowGroup)
build-app.sh                  # MODIFY: add LSUIElement=true to Info.plist
Tests/MemeFinderTests/
  HotKeyModifiersTests.swift  # NEW
```

The reindex/cancel wiring currently inlined in `MemeFinderApp.swift` moves verbatim into `AppDelegate`.

---

### Task 1: HotKey modifier helpers (pure, tested)

**Files:**
- Create: `Sources/MemeFinder/Logic/HotKeyModifiers.swift`
- Test: `Tests/MemeFinderTests/HotKeyModifiersTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `func carbonModifiers(command: Bool, control: Bool, option: Bool, shift: Bool) -> UInt32` — OR of Carbon masks (`cmdKey=256`, `controlKey=4096`, `optionKey=2048`, `shiftKey=512`); 0 when all false.
  - `enum HotKeyConstants { static let mKeyCode: UInt32 = 46 }`.

- [ ] **Step 1: Write the failing tests**

`Tests/MemeFinderTests/HotKeyModifiersTests.swift`:
```swift
import Testing
@testable import MemeFinder

@Test func carbonModifiersCombinesCommandAndControl() {
    // Carbon: cmdKey = 0x0100 (256), controlKey = 0x1000 (4096)
    #expect(carbonModifiers(command: true, control: true, option: false, shift: false) == 256 | 4096)
}

@Test func carbonModifiersEachFlagContributesIndependently() {
    #expect(carbonModifiers(command: true, control: false, option: false, shift: false) == 256)
    #expect(carbonModifiers(command: false, control: true, option: false, shift: false) == 4096)
    #expect(carbonModifiers(command: false, control: false, option: true, shift: false) == 2048)
    #expect(carbonModifiers(command: false, control: false, option: false, shift: true) == 512)
}

@Test func carbonModifiersEmptyIsZero() {
    #expect(carbonModifiers(command: false, control: false, option: false, shift: false) == 0)
}

@Test func mKeyCodeIs46() {
    #expect(HotKeyConstants.mKeyCode == 46)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HotKeyModifiersTests 2>&1 | tail -20`
Expected: FAIL — `carbonModifiers` / `HotKeyConstants` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/MemeFinder/Logic/HotKeyModifiers.swift`:
```swift
import Foundation
import Carbon.HIToolbox

public func carbonModifiers(command: Bool, control: Bool, option: Bool, shift: Bool) -> UInt32 {
    var mask: UInt32 = 0
    if command { mask |= UInt32(cmdKey) }
    if control { mask |= UInt32(controlKey) }
    if option  { mask |= UInt32(optionKey) }
    if shift   { mask |= UInt32(shiftKey) }
    return mask
}

public enum HotKeyConstants {
    public static let mKeyCode: UInt32 = UInt32(kVK_ANSI_M)  // 46
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HotKeyModifiersTests 2>&1 | tail -20`
Expected: PASS (4 tests). The Carbon constants `cmdKey`/`controlKey`/`optionKey`/`shiftKey` equal 256/4096/2048/512, and `kVK_ANSI_M` equals 46.

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/Logic/HotKeyModifiers.swift Tests/MemeFinderTests/HotKeyModifiersTests.swift
git commit -m "feat: add Carbon hotkey modifier helpers"
```

---

### Task 2: GlobalHotKey Carbon wrapper

**Files:**
- Create: `Sources/MemeFinder/Services/GlobalHotKey.swift`
- Test: build verification (Carbon event registration needs a run loop; the testable math lives in Task 1)

**Interfaces:**
- Consumes: nothing (caller passes keyCode/modifiers, e.g. from `HotKeyConstants` + `carbonModifiers`).
- Produces:
  - `final class GlobalHotKey { init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void); var isRegistered: Bool }` — registers a system-wide hotkey via Carbon; `deinit` unregisters; `handler` runs on the main thread.

- [ ] **Step 1: Write the implementation**

`Sources/MemeFinder/Services/GlobalHotKey.swift`:
```swift
import Foundation
import Carbon.HIToolbox

/// Thin wrapper over Carbon RegisterEventHotKey for a single system-wide hotkey.
/// Registration needs no Accessibility permission. If the combo is already taken,
/// `isRegistered` is false and the handler simply never fires.
public final class GlobalHotKey {
    public private(set) var isRegistered = false

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void
    private let id: UInt32

    // Maps a hotkey id to its instance so the C event callback can dispatch.
    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1

    public init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        self.id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        GlobalHotKey.registry[self.id] = self
        register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let target = GlobalHotKey.registry[hkID.id] {
                DispatchQueue.main.async { target.handler() }
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)

        let hkID = EventHotKeyID(signature: OSType(0x4D454D45), id: id)  // 'MEME'
        let status = RegisterEventHotKey(keyCode, modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = (status == noErr)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        GlobalHotKey.registry[id] = nil
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` (library compiles with Carbon import).

- [ ] **Step 3: Run the full suite (no regressions)**

Run: `swift test 2>&1 | tail -3`
Expected: PASS — existing tests plus Task 1's, all green (47 tests).

- [ ] **Step 4: Commit**

```bash
git add Sources/MemeFinder/Services/GlobalHotKey.swift
git commit -m "feat: add GlobalHotKey Carbon wrapper"
```

---

### Task 3: AppDelegate menu-bar shell + app entry

**Files:**
- Create: `Sources/MemeFinderApp/AppDelegate.swift`
- Modify: `Sources/MemeFinderApp/MemeFinderApp.swift`
- Test: build + manual verification (GUI; no unit test — status item/popover/hotkey are runtime behavior)

**Interfaces:**
- Consumes: `SearchViewModel`, `SettingsViewModel`, `IndexingController`, `LiveGeminiService`, `KeychainSecretStore`, `FolderBookmark`, `AppKitClipboardWriter`, `MemeIndex`, `GlobalHotKey`, `HotKeyConstants`, `carbonModifiers`, `ContentView`, `SettingsView`.
- Produces: a Dock-less menu-bar app whose icon/⌃⌘M toggles a popover with `ContentView`, and whose status menu opens settings, triggers reindex, and quits.

- [ ] **Step 1: Write the AppDelegate**

`Sources/MemeFinderApp/AppDelegate.swift`:
```swift
import AppKit
import SwiftUI
import MemeFinder

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let search: SearchViewModel
    private let settings: SettingsViewModel
    private let indexing: IndexingController
    private let indexURL: URL
    private let bookmark: FolderBookmark

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var hotKey: GlobalHotKey?
    private var reindexTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?

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
    }

    @objc private func statusButtonClicked() {
        guard let event = NSApp.currentEvent else { togglePopover(); return }
        if event.type == .rightMouseUp {
            statusItem?.menu = makeMenu()
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil  // restore left-click toggle
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

    @objc private func reindexNow() {
        reindexTask?.cancel()
        reindexTask = Task { @MainActor in
            guard let folder = bookmark.resolve() else { return }
            let existing = MemeIndex.load(from: indexURL)
            let newIndex = await indexing.reindex(folder: folder, existing: existing)
            search.updateIndex(newIndex)
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(
                vm: settings,
                indexing: indexing,
                onReindex: { [weak self] in self?.reindexNow() },
                onCancel: { [weak self] in self?.reindexTask?.cancel() }
            ))
            let window = NSWindow(contentViewController: host)
            window.title = "MemeFinder 設定"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
```
Note: `menu.addItem(withTitle:action:keyEquivalent:)` returns the created `NSMenuItem`, so `menu.addItem(...).target = self` assigns the target on that returned item in one statement — valid Swift. If any of those lines fails to compile, split it into `let item = menu.addItem(...); item.target = self`.

- [ ] **Step 2: Rewrite the app entry**

Replace `Sources/MemeFinderApp/MemeFinderApp.swift` with:
```swift
import SwiftUI

@main
struct MemeFinderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 3: Build both targets**

Run:
```bash
swift build 2>&1 | tail -5
swift build -c release 2>&1 | grep -iE "error|warning" || echo clean
```
Expected: builds; `clean` (no warnings). If the chained `.target = self` on `addItem` does not compile, split into a local `let item = menu.addItem(...); item.target = self` per line and rebuild.

- [ ] **Step 4: Run the full suite (no regressions)**

Run: `swift test 2>&1 | tail -3`
Expected: PASS (47 tests; view-layer change doesn't touch tested library logic).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinderApp/AppDelegate.swift Sources/MemeFinderApp/MemeFinderApp.swift
git commit -m "feat: menu-bar app with status item, popover, and global hotkey"
```

---

### Task 4: Hide Dock icon (LSUIElement) + bundle verification

**Files:**
- Modify: `build-app.sh`
- Test: bundle build + plist lint + manual launch verification

**Interfaces:**
- Consumes: the built `MemeFinderApp` executable.
- Produces: `MemeFinder.app` whose Info.plist has `LSUIElement = true` (no Dock icon).

- [ ] **Step 1: Add LSUIElement to the Info.plist heredoc**

In `build-app.sh`, inside the `Info.plist` `<dict>`, add this key/value (next to `NSHighResolutionCapable`):
```xml
  <key>LSUIElement</key><true/>
```

- [ ] **Step 2: Build the bundle and lint the plist**

Run:
```bash
./build-app.sh && plutil -lint MemeFinder.app/Contents/Info.plist
plutil -extract LSUIElement raw MemeFinder.app/Contents/Info.plist
```
Expected: `Built MemeFinder.app`, plist `OK`, and `LSUIElement` prints `true`.

- [ ] **Step 3: Manual verification (user-run; GUI cannot be tested headless)**

These steps require a desktop session — do NOT run `open` in a headless agent; hand them to the user:
1. `open MemeFinder.app` → no Dock icon appears; a 🙂 icon appears in the menu bar.
2. Press ⌃⌘M → search popover appears; press again → it closes.
3. Right-click the menu-bar icon → menu shows 搜尋… / 設定… / 重新索引 / 結束; "設定…" opens the settings window; set key + folder, "重新索引" runs with progress.
4. In the popover: browse shows all images newest-first; typing searches; clicking copies to clipboard.

- [ ] **Step 4: Commit**

```bash
git add build-app.sh
git commit -m "feat: hide Dock icon via LSUIElement (pure menu-bar app)"
```

---

## Self-Review

**Spec coverage:**
- §3.1 HotKeyModifiers pure helpers + mKeyCode → Task 1 ✓
- §3.2 GlobalHotKey Carbon wrapper (isRegistered, main-thread handler, deinit unregister) → Task 2 ✓
- §3.3 AppDelegate: NSStatusItem + NSPopover(ContentView), togglePopover via icon AND hotkey, status menu (search/settings/reindex/quit), settings NSWindow(SettingsView), reindex/cancel wiring moved from App → Task 3 ✓
- §3.3 app entry = adaptor + empty Settings scene (no WindowGroup) → Task 3 ✓
- §3.4 LSUIElement Dock hide → Task 4 ✓
- §5 hotkey registration failure non-fatal → Task 2 (`isRegistered` flag, no crash) ✓
- §7 tests (carbonModifiers, mKeyCode, no regressions) + manual GUI verification list → Tasks 1, 4 ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. Task 3 flags the one compile risk (chained `.target` on `addItem`) with an explicit fallback. Manual GUI steps are explicitly user-run, not agent-run, since headless cannot exercise them.

**Type consistency:** `carbonModifiers(command:control:option:shift:)`, `HotKeyConstants.mKeyCode`, `GlobalHotKey(keyCode:modifiers:handler:)`/`isRegistered`, and the existing view-model constructors (`SearchViewModel(service:clipboard:index:)`, `SettingsViewModel(secrets:bookmark:)`, `IndexingController(service:indexURL:)`, `SettingsView(vm:indexing:onReindex:onCancel:)`, `ContentView(vm:)`) match their definitions verified in the current `MemeFinderApp.swift`. ✓
