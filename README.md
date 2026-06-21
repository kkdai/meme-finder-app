# MemeFinder

<img width="899" height="517" alt="image" src="https://github.com/user-attachments/assets/b46cc843-d88c-40bf-8ec0-a8d36ce062f4" />


一個原生的 **macOS 迷因搜尋小工具**：指定一個本機迷因圖資料夾，用 **Google Gemini** 自動幫每張圖建立索引（讀出圖中文字、生成描述與標籤、產生語意向量），之後在搜尋框打中文 → 立刻出現最相關的迷因圖 → **點一下就複製到剪貼簿**，可直接貼到 LINE / Slack / 訊息。

> 靈感來自 [ShiQu1218/MemeTalk](https://github.com/ShiQu1218/MemeTalk)（Python/Streamlit 的本地迷因語意搜尋系統），改寫成輕量的原生 macOS App。

---

## ✨ 主要功能

- 🔎 **中文語意搜尋** — 打「謝謝」「無言」「好棒」就能找到對應的梗圖，採 **語意向量（cosine 相似度）+ 關鍵字加權** 混合排序。
- 🖼️ **瀏覽全部** — 還沒打字前，下方直接列出所有已索引的圖，**由最新往前排**（依檔案修改時間）。
- 🤖 **AI 自動標註** — 索引時用 Gemini 視覺模型讀出圖中文字（OCR）、生成繁中描述、主題標籤與情緒。
- 📋 **點圖即複製** — 點任一張圖，圖片即進入系統剪貼簿，可直接貼上。
- ⚡ **增量索引** — 只處理新增/變動的圖，已索引且未改動的自動跳過；索引進度即時顯示。
- 🔐 **金鑰安全** — Gemini API 金鑰存在 macOS **Keychain**（介面遮蔽顯示），即存即生效、不需重開 App。
- 📦 **免完整 Xcode** — 用 Swift Package Manager 建置，再打包成 `MemeFinder.app`。

---

## 🧱 技術架構

- **語言/框架：** Swift 6 / SwiftUI / AppKit（`NSPasteboard`）
- **建置：** Swift Package Manager（不需安裝完整 Xcode）
- **平台：** macOS 14+（Apple Silicon 與 Intel）
- **AI：** Google Gemini REST API
  - 視覺標註：`gemini-3-flash-preview`
  - 語意嵌入：`gemini-embedding-2`（768 維）
- **測試：** Swift Testing（33 個測試，Gemini 一律以 protocol mock，不打真實 API）

專案拆成兩個 target：

| Target | 類型 | 內容 |
|--------|------|------|
| `MemeFinder` | library | 邏輯、模型、服務、ViewModel（全部有單元測試） |
| `MemeFinderApp` | executable | SwiftUI 畫面 + `@main` App（薄殼，依賴上面的函式庫） |

資料流：

```
資料夾 → Indexer（Gemini 視覺 + 嵌入）→ 本機索引檔 index.json
打字查詢 → Gemini 嵌入 → cosine 相似度排序（+關鍵字加權）→ 結果牆 → 點圖 → 剪貼簿
```

---

## 🚀 開始使用

### 需求
- macOS 14 或以上
- 已安裝 Swift 6 工具鏈（`swift --version`）
- 一組 **Gemini API 金鑰** — 到 [Google AI Studio](https://aistudio.google.com/apikey) 免費申請
- 一個裝有迷因圖的資料夾（`.jpg / .jpeg / .png / .webp`）

### 建置 App

```bash
git clone git@github.com:kkdai/meme-finder-app.git
cd meme-finder-app
./build-app.sh          # 產生 MemeFinder.app
open MemeFinder.app
```

開發時也可以直接：

```bash
swift run MemeFinderApp   # 直接執行
swift test                # 跑測試
```

### 設定與使用
1. 開啟 App，按 `⌘,` 進設定。
2. 貼上 **Gemini API 金鑰** → 按「儲存」。
3. 「選擇資料夾…」指向你的迷因圖資料夾。
4. 按 **「重新索引」** — Gemini 會逐張建立索引，進度條顯示 `N/M`。
5. 回主畫面：先看到所有圖（最新在前）；在搜尋框打字即可語意搜尋；**點圖複製到剪貼簿**。

> 索引結果存在 `~/Library/Application Support/MemeFinder/index.json`，下次開 App 直接可搜，無需重新索引。

---

## 📁 專案結構

```
Sources/
  MemeFinder/            # 函式庫（有測試）
    Logic/               # cosine 相似度、搜尋引擎、Gemini 回應解析、索引器
    Models/              # IndexedImage、MemeIndex（JSON 持久化）、SearchResult
    Services/            # GeminiService(REST)、ClipboardWriter、SecretStore(Keychain)、FolderBookmark
    ViewModels/          # SearchViewModel、SettingsViewModel、IndexingController
  MemeFinderApp/         # 執行檔：SwiftUI 畫面 + @main App
Tests/MemeFinderTests/   # Swift Testing 測試
build-app.sh             # 打包成 MemeFinder.app
docs/                    # 設計規格、實作計畫、roadmap
```

設計與計畫文件：
- 設計規格：`docs/superpowers/specs/2026-06-21-memefinder-design.md`
- 實作計畫：`docs/superpowers/plans/2026-06-21-memefinder.md`
- 進度路線圖：`docs/01_plan/project-roadmap.md`

---

## 🗺️ Roadmap

**V1（目前）** — 本機搜尋：AI 自動標註、語意+關鍵字搜尋、點圖複製、瀏覽全部、重新索引。

**V2（規劃中）**
- 線上來源後援（Tenor / Giphy，找不到本機圖時補上）
- 全域快捷鍵、選單列常駐
- 以圖搜圖

---

## 📝 授權

個人專案，請依 repo 設定的授權使用。
