# MemeFinder 效能優化 — 設計文件（縮圖快取 + 索引並行化）

- 日期：2026-06-21
- 狀態：已與使用者確認，待寫實作計畫
- 前置：建立在 [MemeFinder V1](2026-06-21-memefinder-design.md) 之上

## 1. 目標（What & Why）

解決 V1 兩個明顯的效能痛點：

1. **縮圖卡頓** — 目前 `AsyncThumbnail` 在主執行緒同步解碼**全解析度**原圖，圖一多滾動就卡。
2. **索引緩慢** — 目前 `Indexer` 逐張序列呼叫 Gemini（先 annotate 再 embed），上百張圖很慢。

成功標準：
- 滾動大量結果時不卡頓；縮圖在背景生成並快取（記憶體 + 磁碟）。
- 索引以固定併發（4）並行，整體明顯加快；遇 429 自動退避重試；可中途取消並保留已完成部分。
- 既有 33 個測試不退步，新功能皆有對應測試。

## 2. 範圍

### 要做
- `ThumbnailLoader`：ImageIO 背景 downsample + 記憶體/磁碟兩層快取。
- `AsyncThumbnail` 改為真正非同步載入。
- `Indexer` 並行化（併發上限 4、可取消、保留順序、錯誤不中斷、429 退避重試）。
- `LiveGeminiService` HTTP 狀態處理（純函式 `mapResponse`），新增 `GeminiError.rateLimited` 與 `.httpError(Int)`。
- `IndexingController` + `SettingsView` 取消 UI。

### 不做（YAGNI）
- 可調併發數的設定 UI。
- 磁碟快取容量上限 / LRU 清理（先用簡單策略，量大再加）。

## 3. 架構與元件

### 3.1 ThumbnailLoader（library，可測試）
`public actor ThumbnailLoader`
- `init(diskDirectory: URL = <Caches>/MemeFinder/thumbnails, memoryCountLimit: Int = 300)`
- `func thumbnailData(path: String, modifiedAt: Date, maxPixelSize: Int) async -> Data?`
  - 先查記憶體 `NSCache` → 命中即回。
  - 再查磁碟快取檔 → 命中則載入、回填記憶體、回傳。
  - 都沒有 → ImageIO downsample 生成 PNG `Data`，寫磁碟 + 記憶體，回傳。
  - 任一步失敗（檔案不存在/非圖片）→ 回傳 `nil`（呼叫端顯示佔位）。
- 快取鍵 / 磁碟檔名：`cacheKey(path:modifiedAt:maxPixelSize:) -> String`（純函式）= `sha256("\(path)|\(modifiedAt.timeIntervalSince1970)|\(maxPixelSize)")` 的十六進位字串。
- downsample：`CGImageSourceCreateWithURL` + `CGImageSourceCreateThumbnailAtIndex`，選項 `kCGImageSourceCreateThumbnailFromImageAlways=true`、`kCGImageSourceThumbnailMaxPixelSize=maxPixelSize`、`kCGImageSourceCreateThumbnailWithTransform=true`；以 `NSBitmapImageRep` 輸出 PNG `Data`。

### 3.2 AsyncThumbnail（executable）
- 改為 `@State private var image: NSImage?`，`.task(id: path)` 內呼叫共用的 `ThumbnailLoader.thumbnailData(...)`（`maxPixelSize` 取網格縮圖像素，如 280 = 140pt @2x）。
- 取得 `Data` 後在主執行緒轉 `NSImage`（小圖、便宜）。
- 未就緒顯示既有的灰底佔位。
- `ThumbnailLoader` 由 App 建立一份、注入到結果牆（或以單例 `ThumbnailLoader.shared`）。

### 3.3 Indexer 並行化（library）
`buildIndex` 改為併發但對外行為相容：
- 列出資料夾支援副檔名檔案、依路徑排序（同 V1）。
- 已索引且 `path + modifiedAt` 相符者直接重用（不呼叫 Gemini）。
- 其餘以 `withTaskGroup` 執行，**同時最多 `maxConcurrent`（預設 4）** 個任務；每個任務做 annotate→embed 並包重試（見 3.4）。
- 結果收集後**依路徑排序輸出**（穩定順序）。
- 進度：每完成一張（成功或失敗）呼叫一次 `progress(done, total)`，`done` 為已完成數。
- 錯誤：每張失敗記為 `IndexError(path,message)`，不中斷整批。
- 取消：尊重 `Task.isCancelled` — 不再派新任務；回傳目前已完成的部分（含已重用項）。
- 簽章不變：`func buildIndex(folder:existing:progress:) async -> IndexOutcome`。
- 新增 `init(service:maxConcurrent:)`，預設 `maxConcurrent = 4`。

### 3.4 429 退避重試（library）
- 在 Indexer 內，對每張圖的 Gemini 呼叫包一層：
  `retryingOnRateLimit(maxAttempts: 3) { try await annotate/embed }`
  - 僅當捕捉到 `GeminiError.rateLimited` 時退避重試，退避 `0.5s * 2^(attempt-1)`（0.5s、1s、2s）。
  - 其他錯誤立即往上拋（記為 IndexError）。

### 3.5 LiveGeminiService HTTP 狀態（library）
- 新增純函式：`static func mapResponse(data: Data, statusCode: Int) throws -> Data`
  - `200...299` → 回傳 `data`。
  - `429` → `throw GeminiError.rateLimited`。
  - 其他 → `throw GeminiError.httpError(statusCode)`。
- `annotate`/`embed` 改為 `let (data, resp) = try await session.data(...)`，取 `(resp as? HTTPURLResponse)?.statusCode ?? 0`，先過 `mapResponse`，再交給 `GeminiParsing`。
- `GeminiError` 新增 `case rateLimited` 與 `case httpError(Int)`（維持 `Equatable`）。

### 3.6 取消 UI（IndexingController + SettingsView）
- `IndexingController` 取消：App 持有目前 reindex 的 `Task`。
- `SettingsView` 索引進行中（`indexing.progress` 介於 0 與 1）顯示「取消」按鈕，呼叫注入的 `onCancel`。
- App 的 `onReindex` 啟動並保存 `reindexTask`；`onCancel` 呼叫 `reindexTask?.cancel()`。
- 取消後 `IndexingController` 將已完成部分存檔並 `search.updateIndex(...)`，狀態文字顯示「已取消（已索引 N 張）」。

## 4. 資料流（縮圖）
```
結果牆 cell 出現 → AsyncThumbnail.task → ThumbnailLoader
  → 記憶體快取? → 磁碟快取? → ImageIO downsample → (寫兩層快取) → PNG Data → NSImage → 顯示
```

## 5. 錯誤處理
- 縮圖任一步失敗 → 回 `nil`，顯示灰底佔位，不崩潰。
- 索引單張失敗 → IndexError 收集、續跑。
- 429 → 退避重試（上限 3）；仍失敗則記為該圖錯誤。
- 取消 → 保存並回傳已完成部分。

## 6. 測試
- `cacheKey` 純函式：相同輸入穩定、對 `modifiedAt` 與 `maxPixelSize` 敏感。
- `ThumbnailLoader`：對暫存大圖生成縮圖、最大邊 ≤ maxPixelSize；磁碟快取檔產生；第二次呼叫命中（不重生，可用磁碟檔存在 + 內容一致驗證）。
- `mapResponse`：200 回傳、429 → rateLimited、500 → httpError(500)。
- `Indexer` 並行：全部索引、未變動跳過（annotateCalls==0）、錯誤不中斷、**併發峰值 ≤ maxConcurrent**（mock 記錄同時進行數）、rateLimited 重試後成功。
- 既有 `IndexerTests`、全套測試不退步。
- Gemini 一律 mock，不打真實 API。

## 7. 後續（V2）
- 磁碟快取容量上限 / LRU。
- 可調併發數設定。
- 索引改 SQLite + ANN（量大時）。
