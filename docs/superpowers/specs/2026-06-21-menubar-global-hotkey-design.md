# MemeFinder 選單列常駐 + 全域快捷鍵 — 設計文件

- 日期：2026-06-21
- 狀態：已與使用者確認，待寫實作計畫
- 前置：建立在 [MemeFinder V1](2026-06-21-memefinder-design.md) 與 [效能優化](2026-06-21-perf-thumbnails-parallel-index-design.md) 之上

## 1. 目標（What & Why）

把 MemeFinder 從「有獨立主視窗的 App」改成**純選單列常駐工具**：右上選單列一個 icon，按固定全域快捷鍵 **⌃⌘M** 或點 icon → 彈出搜尋浮窗，打字搜尋 → 點圖複製 → 自動收起。讓「聊天到一半快速找梗圖」變得順手，不必切視窗。

成功標準：
- App 啟動後不顯示 Dock 圖示、不開主視窗，只在選單列出現 icon。
- 按 ⌃⌘M 或點 icon 彈出搜尋浮窗；浮窗內沿用既有的搜尋／瀏覽／點圖複製。
- 選單列選單可進入設定（選資料夾、金鑰、重新索引）與結束 App。
- 既有 43 個測試不退步；新增的可測邏輯有對應測試。

## 2. 範圍

### 要做
- App 進入點改為選單列常駐：`NSStatusItem` + `NSPopover`（經 `AppDelegate`）裝既有 `ContentView`。
- `LSUIElement = true` 隱藏 Dock 圖示（純選單列 App）。
- 固定全域快捷鍵 ⌃⌘M（Carbon `RegisterEventHotKey`）切換浮窗顯示。
- 設定與重新索引從選單列入口進入（沿用既有 `SettingsView` / `IndexingController`）。

### 不做（YAGNI）
- 可自訂快捷鍵。
- 開機自動啟動（login item）。
- 多組快捷鍵。

## 3. 架構與元件

各元件單一職責、可獨立理解；可測的純邏輯與 GUI 殼分離。

### 3.1 HotKeyModifiers（library，純函式，可測試）
- `func carbonModifiers(command: Bool, control: Bool, option: Bool, shift: Bool) -> UInt32` — 把布林修飾鍵組合成 Carbon `cmdKey/controlKey/optionKey/shiftKey` 的位元 OR 值（純函式，好測）。
- 常數 `enum HotKeyConstants { static let mKeyCode: UInt32 = 46 }`（macOS `kVK_ANSI_M` = 46）。

### 3.2 GlobalHotKey（library，薄 Carbon 包裝）
- `final class GlobalHotKey`：`init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void)` 用 `RegisterEventHotKey` + `InstallEventHandler` 註冊；`deinit` 解除註冊（`UnregisterEventHotKey`）。
- `var isRegistered: Bool`：註冊成功與否（被其他 App 佔用時為 false）。
- handler 在主執行緒呼叫。
- 這層本身難在 headless 單元測試（牽涉事件迴圈），但邏輯薄；以手動驗證為主，§3.1 的純函式負責自動測試。

### 3.3 MenuBarController / AppDelegate（executable）
- **採 `NSStatusItem` + `NSPopover`（經 `NSApplicationDelegateAdaptor`），不用 `MenuBarExtra`。** 原因：全域快捷鍵必須能**程式化切換**浮窗顯示，而 `MenuBarExtra` 沒有乾淨暴露「以程式控制呈現狀態」的綁定；`NSPopover` 的 `show(relativeTo:)` / `performClose()` 可完全程式控制，最適合快捷鍵 toggle。
- `@main` App 仍是 SwiftUI `App`，但 body 用空的 `Settings { SettingsView(...) }` scene（提供 `⌘,` 設定視窗、沿用既有金鑰/資料夾/重新索引/取消 wiring），並以 `@NSApplicationDelegateAdaptor` 掛上 `AppDelegate`。
- `AppDelegate`（`MenuBarController`）職責：
  - 建立 `NSStatusItem`（選單列 icon，systemImage 類似 `face.smiling`）。
  - 建立 `NSPopover`，內容 = `NSHostingController(rootView: ContentView(vm: search))`。
  - 左鍵點 icon → toggle popover；持有 `GlobalHotKey`（⌃⌘M）其 handler 也呼叫同一個 `togglePopover()`。
  - 提供「設定…」（開啟 Settings 視窗 / 啟用 App）、「重新索引」、「結束」入口——以 icon 的右鍵選單（`NSMenu`）或浮窗內按鈕呈現。
  - popover 失焦自動關閉（`popover.behavior = .transient`）。
- 既有的 `SearchViewModel` / `SettingsViewModel` / `IndexingController` 由 `AppDelegate` 建立並注入（沿用目前 `MemeFinderApp.init` 的建構邏輯，只是移到 delegate）。

### 3.4 Dock 隱藏
- `build-app.sh` 產生的 `Info.plist` 加入 `LSUIElement = true`（亦稱 `Application is agent`），App 不出現在 Dock 與 ⌘Tab。

## 4. 資料流
```
⌃⌘M（GlobalHotKey）/ 點選單列 icon → 切換 MenuBarExtra 浮窗
  浮窗 → ContentView（既有：搜尋 / 瀏覽全部 / 點圖複製）
選單列入口 → Settings（既有 SettingsView：金鑰 / 資料夾 / 重新索引 / 取消）
```
既有 `SearchViewModel` / `SettingsViewModel` / `IndexingController` / `ThumbnailLoader` 全部沿用，只更換 App「殼」。

## 5. 權限
- 固定 Carbon `RegisterEventHotKey` **不需**輔助使用（Accessibility）權限。
- 非沙盒 App 直接可註冊。
- ⌃⌘M 若被其他 App 佔用 → 註冊回傳失敗，`isRegistered == false`；App 不崩潰，仍可點選單列 icon 使用。

## 6. 錯誤處理
- 快捷鍵註冊失敗 → 靜默略過，記錄；icon 入口照常可用。
- 浮窗開啟但尚未設定金鑰/資料夾 → ContentView 既有提示照常顯示。

## 7. 測試
- `carbonModifiers`：command+control 組合對應正確位元；各旗標獨立貢獻；全 false → 0。
- `HotKeyConstants.mKeyCode == 46`。
- 既有 43 測試不退步。
- ⚠️ 選單列浮窗呈現、全域快捷鍵實際觸發、Dock 隱藏屬 GUI 行為，**headless 無法自動測試**，計畫中標明需使用者手動驗證（按 ⌃⌘M 彈窗、點 icon、設定可開、無 Dock 圖示）。

## 8. 後續（V2）
- 可自訂快捷鍵（錄鍵 UI + 持久化 + 重註冊）。
- 開機自動啟動（`SMAppService` login item）。
