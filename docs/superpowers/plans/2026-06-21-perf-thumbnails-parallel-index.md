# MemeFinder Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make thumbnails load off-main with a memory+disk cache, and parallelize Gemini indexing (concurrency 4, 429 backoff-retry, cancellable) — without regressing the existing 33 tests.

**Architecture:** Add a `ThumbnailLoader` actor (ImageIO downsample + NSCache + disk cache) in the library and make `AsyncThumbnail` consume it asynchronously. Rewrite `Indexer.buildIndex` to run image work in a bounded `withTaskGroup` with per-image rate-limit retry and cooperative cancellation, and teach `LiveGeminiService` to map HTTP status codes to distinct `GeminiError` cases. Wire a cancel button through `IndexingController`/`SettingsView`.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ImageIO, CryptoKit, Swift Testing. Library target `MemeFinder`; executable target `MemeFinderApp`.

## Global Constraints

- `MemeFinder` is a library target (view models import Combine, no SwiftUI); `MemeFinderApp` is the executable (SwiftUI views import SwiftUI + MemeFinder).
- Test framework: Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`); run `swift test`.
- All Gemini access stays behind `GeminiService`; tests mock it, never call the network.
- Index concurrency default: `maxConcurrent = 4`. Rate-limit retry: max 3 attempts, backoff `retryBaseDelay * 2^(attempt-1)` seconds, default `retryBaseDelay = 0.5`.
- Thumbnail disk cache: `<Caches>/MemeFinder/thumbnails/`; cache key/file name = `sha256("\(path)|\(modifiedAt.timeIntervalSince1970)|\(maxPixelSize)")` hex; grid thumbnail `maxPixelSize = 280`.
- Output must stay pristine (no compiler warnings beyond none).
- Existing public signatures that must NOT break: `Indexer.buildIndex(folder:existing:progress:) async -> IndexOutcome`, `IndexingController.reindex(folder:existing:) async -> MemeIndex`, `GeminiService.{annotate,embed}`, the static `LiveGeminiService.{annotateRequest,embedRequest}` builders.
- Commit after every task with a `feat:`/`test:`/`fix:` prefixed message.

---

## File Structure

```
Sources/MemeFinder/
  Logic/
    ThumbnailImaging.swift     # NEW: thumbnailCacheKey() + downsampledPNGData() — pure helpers
    Indexer.swift              # MODIFY: bounded-concurrency buildIndex + retry + cancellation
  Services/
    ThumbnailLoader.swift      # NEW: actor, memory(NSCache)+disk cache around the helpers
    GeminiService.swift        # MODIFY: GeminiError.rateLimited/.httpError + mapResponse + status handling
  ViewModels/
    IndexingController.swift   # MODIFY: status text reflects cancellation
Sources/MemeFinderApp/
  ResultGridView.swift         # MODIFY: AsyncThumbnail uses ThumbnailLoader.shared async
  SettingsView.swift           # MODIFY: cancel button while indexing
  MemeFinderApp.swift          # MODIFY: hold reindex Task, wire onCancel
Tests/MemeFinderTests/
  ThumbnailImagingTests.swift  # NEW
  ThumbnailLoaderTests.swift   # NEW
  GeminiParsingTests.swift     # MODIFY: add mapResponse tests
  IndexerTests.swift           # MODIFY: add concurrency/retry/cancel tests
```

---

### Task 1: Thumbnail helpers (cache key + ImageIO downsample)

**Files:**
- Create: `Sources/MemeFinder/Logic/ThumbnailImaging.swift`
- Test: `Tests/MemeFinderTests/ThumbnailImagingTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `func thumbnailCacheKey(path: String, modifiedAt: Date, maxPixelSize: Int) -> String` — 64-char sha256 hex of `"\(path)|\(modifiedAt.timeIntervalSince1970)|\(maxPixelSize)"`.
  - `func downsampledPNGData(path: String, maxPixelSize: Int) -> Data?` — ImageIO thumbnail as PNG data; `nil` if the file is missing/not an image.

- [ ] **Step 1: Write the failing tests**

`Tests/MemeFinderTests/ThumbnailImagingTests.swift`:
```swift
import Testing
import Foundation
import AppKit
@testable import MemeFinder

@Test func cacheKeyIsStableAndSensitive() {
    let d = Date(timeIntervalSince1970: 100)
    let a = thumbnailCacheKey(path: "/x.png", modifiedAt: d, maxPixelSize: 280)
    #expect(a == thumbnailCacheKey(path: "/x.png", modifiedAt: d, maxPixelSize: 280))
    #expect(a.count == 64)
    #expect(a != thumbnailCacheKey(path: "/x.png", modifiedAt: d, maxPixelSize: 281))
    #expect(a != thumbnailCacheKey(path: "/x.png", modifiedAt: Date(timeIntervalSince1970: 101), maxPixelSize: 280))
    #expect(a != thumbnailCacheKey(path: "/y.png", modifiedAt: d, maxPixelSize: 280))
}

private func writePNG(_ side: Int) throws -> URL {
    let img = NSImage(size: NSSize(width: side, height: side))
    img.lockFocus(); NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: side, height: side)); img.unlockFocus()
    let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
    try png.write(to: url)
    return url
}

@Test func downsampleProducesSmallerImage() throws {
    let url = try writePNG(200)
    let data = try #require(downsampledPNGData(path: url.path, maxPixelSize: 64))
    let rep = try #require(NSBitmapImageRep(data: data))
    #expect(max(rep.pixelsWide, rep.pixelsHigh) <= 64)
    #expect(rep.pixelsWide > 0)
}

@Test func downsampleReturnsNilForNonImage() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
    try Data("not an image".utf8).write(to: url)
    #expect(downsampledPNGData(path: url.path, maxPixelSize: 64) == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ThumbnailImagingTests 2>&1 | tail -20`
Expected: FAIL — `thumbnailCacheKey` / `downsampledPNGData` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/MemeFinder/Logic/ThumbnailImaging.swift`:
```swift
import Foundation
import CryptoKit
import ImageIO
import AppKit

public func thumbnailCacheKey(path: String, modifiedAt: Date, maxPixelSize: Int) -> String {
    let input = "\(path)|\(modifiedAt.timeIntervalSince1970)|\(maxPixelSize)"
    return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
}

public func downsampledPNGData(path: String, maxPixelSize: Int) -> Data? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ThumbnailImagingTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/Logic/ThumbnailImaging.swift Tests/MemeFinderTests/ThumbnailImagingTests.swift
git commit -m "feat: add thumbnail cache key and ImageIO downsample helpers"
```

---

### Task 2: ThumbnailLoader actor (memory + disk cache)

**Files:**
- Create: `Sources/MemeFinder/Services/ThumbnailLoader.swift`
- Test: `Tests/MemeFinderTests/ThumbnailLoaderTests.swift`

**Interfaces:**
- Consumes: `thumbnailCacheKey`, `downsampledPNGData`.
- Produces:
  - `actor ThumbnailLoader { init(diskDirectory: URL? = nil, memoryCountLimit: Int = 300); func thumbnailData(path: String, modifiedAt: Date, maxPixelSize: Int) -> Data? }`
  - `extension ThumbnailLoader { static let shared: ThumbnailLoader }`
  - Lookup order: memory cache → disk cache (refills memory) → generate via `downsampledPNGData` (writes both caches). Returns `nil` if generation fails.

- [ ] **Step 1: Write the failing test**

`Tests/MemeFinderTests/ThumbnailLoaderTests.swift`:
```swift
import Testing
import Foundation
import AppKit
@testable import MemeFinder

private func writePNG(_ side: Int) throws -> (URL, Date) {
    let img = NSImage(size: NSSize(width: side, height: side))
    img.lockFocus(); NSColor.blue.drawSwatch(in: NSRect(x: 0, y: 0, width: side, height: side)); img.unlockFocus()
    let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
    try png.write(to: url)
    let mtime = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date
    return (url, mtime)
}

@Test func loaderGeneratesCachesToDiskAndReturnsSameData() async throws {
    let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let loader = ThumbnailLoader(diskDirectory: cacheDir)
    let (url, mtime) = try writePNG(200)

    let d1 = try #require(await loader.thumbnailData(path: url.path, modifiedAt: mtime, maxPixelSize: 64))
    let key = thumbnailCacheKey(path: url.path, modifiedAt: mtime, maxPixelSize: 64)
    #expect(FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent(key + ".png").path))

    let d2 = await loader.thumbnailData(path: url.path, modifiedAt: mtime, maxPixelSize: 64)
    #expect(d2 == d1)  // served from cache, identical bytes
}

@Test func loaderReturnsNilForMissingFile() async {
    let loader = ThumbnailLoader(diskDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let data = await loader.thumbnailData(path: "/nope/missing.png", modifiedAt: Date(), maxPixelSize: 64)
    #expect(data == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ThumbnailLoaderTests 2>&1 | tail -20`
Expected: FAIL — `ThumbnailLoader` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/MemeFinder/Services/ThumbnailLoader.swift`:
```swift
import Foundation

public actor ThumbnailLoader {
    private let diskDirectory: URL
    private let memory = NSCache<NSString, NSData>()

    public init(diskDirectory: URL? = nil, memoryCountLimit: Int = 300) {
        self.diskDirectory = diskDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MemeFinder/thumbnails")
        memory.countLimit = memoryCountLimit
        try? FileManager.default.createDirectory(at: self.diskDirectory, withIntermediateDirectories: true)
    }

    public func thumbnailData(path: String, modifiedAt: Date, maxPixelSize: Int) -> Data? {
        let key = thumbnailCacheKey(path: path, modifiedAt: modifiedAt, maxPixelSize: maxPixelSize)
        let nsKey = key as NSString
        if let cached = memory.object(forKey: nsKey) { return cached as Data }

        let diskURL = diskDirectory.appendingPathComponent(key + ".png")
        if let onDisk = try? Data(contentsOf: diskURL) {
            memory.setObject(onDisk as NSData, forKey: nsKey)
            return onDisk
        }

        guard let data = downsampledPNGData(path: path, maxPixelSize: maxPixelSize) else { return nil }
        memory.setObject(data as NSData, forKey: nsKey)
        try? data.write(to: diskURL)
        return data
    }
}

extension ThumbnailLoader {
    public static let shared = ThumbnailLoader()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ThumbnailLoaderTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/Services/ThumbnailLoader.swift Tests/MemeFinderTests/ThumbnailLoaderTests.swift
git commit -m "feat: add ThumbnailLoader actor with memory and disk cache"
```

---

### Task 3: AsyncThumbnail loads off-main via ThumbnailLoader

**Files:**
- Modify: `Sources/MemeFinderApp/ResultGridView.swift`
- Test: build verification only (SwiftUI view; the loader is unit-tested in Task 2)

**Interfaces:**
- Consumes: `ThumbnailLoader.shared`.
- Produces: an `AsyncThumbnail` that renders a placeholder until the cached/downsampled image is ready.

- [ ] **Step 1: Replace the AsyncThumbnail implementation**

In `Sources/MemeFinderApp/ResultGridView.swift`, replace the existing `struct AsyncThumbnail` with:
```swift
struct AsyncThumbnail: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: path) {
            let mtime = ((try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date) ?? Date()
            if let data = await ThumbnailLoader.shared.thumbnailData(path: path, modifiedAt: mtime, maxPixelSize: 280) {
                image = NSImage(data: data)
            }
        }
    }
}
```
Ensure the file still has `import SwiftUI`, `import AppKit` (add if missing), and `import MemeFinder` at the top.

- [ ] **Step 2: Run the full test suite (no regressions)**

Run: `swift test 2>&1 | tail -3`
Expected: PASS — existing suite green (37 tests after Tasks 1–2).

- [ ] **Step 3: Verify both targets build**

Run: `swift build 2>&1 | tail -3 && swift build -c release 2>&1 | grep -iE "error|warning" || echo clean`
Expected: builds; `clean` (no warnings).

- [ ] **Step 4: Commit**

```bash
git add Sources/MemeFinderApp/ResultGridView.swift
git commit -m "feat: load grid thumbnails off-main via ThumbnailLoader"
```

---

### Task 4: Gemini HTTP status mapping (rateLimited / httpError)

**Files:**
- Modify: `Sources/MemeFinder/Services/GeminiService.swift`
- Test: `Tests/MemeFinderTests/GeminiParsingTests.swift` (append)

**Interfaces:**
- Consumes: existing `LiveGeminiService` request builders, `GeminiParsing`.
- Produces:
  - `GeminiError` gains `case rateLimited` and `case httpError(Int)` (stays `Equatable`).
  - `static func LiveGeminiService.mapResponse(data: Data, statusCode: Int) throws -> Data` — returns `data` for 2xx, throws `.rateLimited` for 429, `.httpError(code)` otherwise.
  - `annotate`/`embed` run the HTTP response through `mapResponse` before parsing.

- [ ] **Step 1: Write the failing test**

Append to `Tests/MemeFinderTests/GeminiParsingTests.swift`:
```swift
@Test func mapResponseHandlesStatusCodes() throws {
    #expect(try LiveGeminiService.mapResponse(data: Data([1, 2]), statusCode: 200) == Data([1, 2]))
    #expect(throws: GeminiError.rateLimited) {
        _ = try LiveGeminiService.mapResponse(data: Data(), statusCode: 429)
    }
    #expect(throws: GeminiError.httpError(500)) {
        _ = try LiveGeminiService.mapResponse(data: Data(), statusCode: 500)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter mapResponseHandlesStatusCodes 2>&1 | tail -20`
Expected: FAIL — `mapResponse` / `rateLimited` / `httpError` not defined.

- [ ] **Step 3: Add the error cases, mapResponse, and wire status handling**

In `Sources/MemeFinder/Services/GeminiService.swift`, extend the error enum:
```swift
public enum GeminiError: Error, Equatable {
    case badResponse(String)
    case missingKey
    case rateLimited
    case httpError(Int)
}
```
Add the static mapper inside `LiveGeminiService`:
```swift
    public static func mapResponse(data: Data, statusCode: Int) throws -> Data {
        switch statusCode {
        case 200...299: return data
        case 429: throw GeminiError.rateLimited
        default: throw GeminiError.httpError(statusCode)
        }
    }
```
Change the two instance methods to check status first (keep `currentKey()` first):
```swift
    public func annotate(imageData: Data, mimeType: String) async throws -> Annotation {
        let key = try currentKey()
        let (data, resp) = try await session.data(for: Self.annotateRequest(apiKey: key, imageData: imageData, mimeType: mimeType))
        let checked = try Self.mapResponse(data: data, statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0)
        return try GeminiParsing.annotation(fromGenerateContent: checked)
    }

    public func embed(text: String) async throws -> [Float] {
        let key = try currentKey()
        let (data, resp) = try await session.data(for: Self.embedRequest(apiKey: key, text: text))
        let checked = try Self.mapResponse(data: data, statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0)
        return try GeminiParsing.embedding(fromEmbedContent: checked)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GeminiParsingTests 2>&1 | tail -20`
Expected: PASS (all GeminiParsing tests including the new one).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/Services/GeminiService.swift Tests/MemeFinderTests/GeminiParsingTests.swift
git commit -m "feat: map Gemini HTTP status to rateLimited/httpError errors"
```

---

### Task 5: Parallel Indexer (bounded concurrency + retry + cancellation)

**Files:**
- Modify: `Sources/MemeFinder/Logic/Indexer.swift`
- Test: `Tests/MemeFinderTests/IndexerTests.swift` (append; keep existing tests)

**Interfaces:**
- Consumes: `GeminiService`, `GeminiError.rateLimited`, `IndexedImage`, `MemeIndex`.
- Produces:
  - `Indexer.init(service: GeminiService, maxConcurrent: Int = 4, retryBaseDelay: Double = 0.5)`.
  - `buildIndex(folder:existing:progress:) async -> IndexOutcome` (unchanged signature) now: runs unchanged-entry reuse + new-image annotate→embed across at most `maxConcurrent` concurrent tasks; retries only `GeminiError.rateLimited` up to 3 attempts with exponential backoff; fires `progress(done,total)` once per completed file; collects `IndexError`s without aborting; honors `Task.isCancelled` (stops scheduling, returns the partial result); outputs images sorted by path.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/MemeFinderTests/IndexerTests.swift`:
```swift
import Foundation

private final class ConcurrencyService: GeminiService, @unchecked Sendable {
    let lock = NSLock()
    var current = 0
    var peak = 0
    func annotate(imageData: Data, mimeType: String) async throws -> Annotation {
        lock.lock(); current += 1; peak = max(peak, current); lock.unlock()
        try? await Task.sleep(nanoseconds: 20_000_000)
        lock.lock(); current -= 1; lock.unlock()
        return Annotation(ocrText: "t", description: "d", tags: ["x"], emotion: "e")
    }
    func embed(text: String) async throws -> [Float] { [1, 0] }
}

private final class FlakyEmbedService: GeminiService, @unchecked Sendable {
    let lock = NSLock(); var embedCalls = 0
    func annotate(imageData: Data, mimeType: String) async throws -> Annotation {
        Annotation(ocrText: "t", description: "d", tags: ["x"], emotion: "e")
    }
    func embed(text: String) async throws -> [Float] {
        lock.lock(); embedCalls += 1; let n = embedCalls; lock.unlock()
        if n == 1 { throw GeminiError.rateLimited }
        return [1, 0]
    }
}

private final class SlowService: GeminiService, @unchecked Sendable {
    func annotate(imageData: Data, mimeType: String) async throws -> Annotation {
        try? await Task.sleep(nanoseconds: 30_000_000)
        return Annotation(ocrText: "t", description: "d", tags: ["x"], emotion: "e")
    }
    func embed(text: String) async throws -> [Float] { [1, 0] }
}

private func folderWith(_ count: Int) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for i in 0..<count { try Data([0]).write(to: dir.appendingPathComponent("img\(i).png")) }
    return dir
}

@Test func parallelIndexingRespectsConcurrencyCap() async throws {
    let dir = try folderWith(12)
    let svc = ConcurrencyService()
    let out = await Indexer(service: svc, maxConcurrent: 4, retryBaseDelay: 0).buildIndex(folder: dir, existing: MemeIndex()) { _, _ in }
    #expect(out.index.images.count == 12)
    #expect(svc.peak <= 4)
    #expect(svc.peak >= 2)  // genuinely parallel
}

@Test func parallelIndexingRetriesOnRateLimit() async throws {
    let dir = try folderWith(1)
    let out = await Indexer(service: FlakyEmbedService(), maxConcurrent: 4, retryBaseDelay: 0).buildIndex(folder: dir, existing: MemeIndex()) { _, _ in }
    #expect(out.index.images.count == 1)
    #expect(out.errors.isEmpty)
}

@Test func cancellationStopsSchedulingEarly() async throws {
    let dir = try folderWith(40)
    let task = Task {
        await Indexer(service: SlowService(), maxConcurrent: 2, retryBaseDelay: 0)
            .buildIndex(folder: dir, existing: MemeIndex()) { _, _ in }
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    task.cancel()
    let out = await task.value
    #expect(out.index.images.count < 40)  // did not finish all 40
}

@Test func parallelIndexingResultsAreSortedByPath() async throws {
    let dir = try folderWith(5)
    let out = await Indexer(service: ConcurrencyService(), maxConcurrent: 4, retryBaseDelay: 0).buildIndex(folder: dir, existing: MemeIndex()) { _, _ in }
    #expect(out.index.images.map(\.path) == out.index.images.map(\.path).sorted())
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter IndexerTests 2>&1 | tail -25`
Expected: FAIL — `Indexer(service:maxConcurrent:retryBaseDelay:)` initializer / behavior not present.

- [ ] **Step 3: Rewrite Indexer with bounded concurrency**

Replace the body of `Sources/MemeFinder/Logic/Indexer.swift` (keep `IndexError`/`IndexOutcome` as-is) with:
```swift
import Foundation

public struct IndexError: Equatable, Sendable { public var path: String; public var message: String }
public struct IndexOutcome: Sendable { public var index: MemeIndex; public var errors: [IndexError] }

public struct Indexer {
    private static let exts: Set<String> = ["jpg", "jpeg", "png", "webp"]
    private let service: GeminiService
    private let maxConcurrent: Int
    private let retryBaseDelay: Double

    public init(service: GeminiService, maxConcurrent: Int = 4, retryBaseDelay: Double = 0.5) {
        self.service = service
        self.maxConcurrent = max(1, maxConcurrent)
        self.retryBaseDelay = retryBaseDelay
    }

    private func mimeType(for ext: String) -> String {
        switch ext { case "png": return "image/png"; case "webp": return "image/webp"; default: return "image/jpeg" }
    }

    private struct WorkResult: Sendable {
        let path: String
        let image: IndexedImage?
        let error: IndexError?
    }

    private func retryingOnRateLimit<T: Sendable>(_ op: @Sendable () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do { return try await op() }
            catch GeminiError.rateLimited {
                attempt += 1
                if attempt >= 3 { throw GeminiError.rateLimited }
                let delay = retryBaseDelay * pow(2.0, Double(attempt - 1))
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            }
        }
    }

    public func buildIndex(folder: URL, existing: MemeIndex,
                           progress: @Sendable (Int, Int) -> Void) async -> IndexOutcome {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { Self.exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.standardizedFileURL.path < $1.standardizedFileURL.path }
        let byPath = Dictionary(uniqueKeysWithValues: existing.images.map { ($0.path, $0) })
        let total = files.count

        var resultsByPath: [String: IndexedImage] = [:]
        var errors: [IndexError] = []
        var done = 0

        await withTaskGroup(of: WorkResult.self) { group in
            var iterator = files.makeIterator()

            func scheduleNext() -> Bool {
                guard !Task.isCancelled, let url = iterator.next() else { return false }
                let path = url.standardizedFileURL.path
                let mtime = ((try? fm.attributesOfItem(atPath: path)[.modificationDate]) as? Date) ?? Date()
                if let prev = byPath[path], prev.modifiedAt == mtime {
                    group.addTask { WorkResult(path: path, image: prev, error: nil) }
                    return true
                }
                let service = self.service
                let mime = mimeType(for: url.pathExtension.lowercased())
                group.addTask {
                    do {
                        let data = try Data(contentsOf: url)
                        let ann = try await retryingOnRateLimit { try await service.annotate(imageData: data, mimeType: mime) }
                        let text = [ann.ocrText, ann.description, ann.tags.joined(separator: " "), ann.emotion].joined(separator: " ")
                        let vec = try await retryingOnRateLimit { try await service.embed(text: text) }
                        let img = IndexedImage(id: path, path: path, modifiedAt: mtime,
                                               ocrText: ann.ocrText, imageDescription: ann.description,
                                               tags: ann.tags, emotion: ann.emotion, embedding: vec)
                        return WorkResult(path: path, image: img, error: nil)
                    } catch {
                        return WorkResult(path: path, image: nil,
                                          error: IndexError(path: path, message: String(describing: error)))
                    }
                }
                return true
            }

            for _ in 0..<maxConcurrent { if !scheduleNext() { break } }
            while let res = await group.next() {
                if let img = res.image { resultsByPath[res.path] = img }
                if let err = res.error { errors.append(err) }
                done += 1
                progress(done, total)
                _ = scheduleNext()
            }
        }

        let ordered = files.map { $0.standardizedFileURL.path }.compactMap { resultsByPath[$0] }
        return IndexOutcome(index: MemeIndex(images: ordered), errors: errors)
    }
}
```
Note: `retryingOnRateLimit` is referenced inside `group.addTask` — call it as `self.retryingOnRateLimit`; since `self` (an `Indexer`) is a value type with only `Sendable` stored properties, capture is safe. If the compiler complains about capturing `self`, bind `let retry = self.retryingOnRateLimit` is not possible for a generic method — instead keep `self.retryingOnRateLimit { ... }` and mark `Indexer: Sendable` (all stored props are Sendable). Add `: Sendable` to the struct declaration if needed for the capture to compile cleanly.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter IndexerTests 2>&1 | tail -25`
Expected: PASS — new concurrency/retry/cancel/order tests plus the original two (`indexesSupportedImagesAndSkipsOthers`, `reusesUnchangedEntriesWithoutCallingGemini`).

- [ ] **Step 5: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: PASS (all tests green).

- [ ] **Step 6: Commit**

```bash
git add Sources/MemeFinder/Logic/Indexer.swift Tests/MemeFinderTests/IndexerTests.swift
git commit -m "feat: parallelize indexer with retry and cancellation"
```

---

### Task 6: Cancel button wiring (IndexingController + SettingsView + App)

**Files:**
- Modify: `Sources/MemeFinder/ViewModels/IndexingController.swift`
- Modify: `Sources/MemeFinderApp/SettingsView.swift`
- Modify: `Sources/MemeFinderApp/MemeFinderApp.swift`
- Test: full-suite + build verification (UI wiring; cancellation logic is unit-tested in Task 5)

**Interfaces:**
- Consumes: `Indexer` (cancellation-aware), `IndexingController.reindex(folder:existing:) async -> MemeIndex`.
- Produces: a cancel button in Settings that cancels the in-flight reindex; status text shows the cancelled/completed state.

- [ ] **Step 1: Make IndexingController status reflect cancellation**

In `Sources/MemeFinder/ViewModels/IndexingController.swift`, change the post-build status assignment in `reindex(...)` so the final lines read:
```swift
        progress = 1.0
        try? outcome.index.save(to: indexURL)
        if Task.isCancelled {
            statusText = "已取消（已索引 \(outcome.index.images.count) 張）"
        } else if outcome.errors.isEmpty {
            statusText = "索引完成（\(outcome.index.images.count) 張）"
        } else {
            statusText = "完成，但有 \(outcome.errors.count) 張失敗"
        }
        return outcome.index
```
(Leave the rest of `reindex` — progress callback, Indexer call — unchanged.)

- [ ] **Step 2: Add a cancel button to SettingsView**

In `Sources/MemeFinderApp/SettingsView.swift`: add a stored `let onCancel: () -> Void` with init parameter (default `{}`), placed after `onReindex`. In the 迷因資料夾 section, next to the reindex button, show a cancel button while indexing:
```swift
                if indexing.progress > 0 && indexing.progress < 1 {
                    Button("取消") { onCancel() }
                }
```

- [ ] **Step 3: Hold and cancel the reindex Task in the App**

In `Sources/MemeFinderApp/MemeFinderApp.swift`: add `@State private var reindexTask: Task<Void, Never>?`. Change the existing `onReindex` closure so it stores its work in `reindexTask` (cancel any previous one first), and pass an `onCancel` closure to `SettingsView` that cancels it. Concretely the `Settings` scene becomes:
```swift
        Settings {
            SettingsView(
                vm: settings,
                indexing: indexingController,
                onReindex: {
                    reindexTask?.cancel()
                    reindexTask = Task {
                        guard let folder = bookmark.resolve() else { return }
                        let existing = MemeIndex.load(from: indexURL)
                        let newIndex = await indexingController.reindex(folder: folder, existing: existing)
                        search.updateIndex(newIndex)
                    }
                },
                onCancel: { reindexTask?.cancel() }
            )
        }
```
Adjust the captured names (`bookmark`, `indexURL`, `indexingController`, `search`) to the actual stored-property names already present in `MemeFinderApp`. Do not change how those properties are created.

- [ ] **Step 4: Run the full suite (no regressions)**

Run: `swift test 2>&1 | tail -3`
Expected: PASS — existing `IndexingControllerTests` still green (the completion-status branch still sets progress 1.0 and saves).

- [ ] **Step 5: Build both targets and the app bundle**

Run:
```bash
swift build 2>&1 | tail -3
swift build -c release 2>&1 | grep -iE "error|warning" || echo clean
./build-app.sh && plutil -lint MemeFinder.app/Contents/Info.plist
```
Expected: builds, `clean`, `Built MemeFinder.app`, plist `OK`. (Headless: do not `open` the app.)

- [ ] **Step 6: Commit**

```bash
git add Sources/MemeFinder/ViewModels/IndexingController.swift Sources/MemeFinderApp/SettingsView.swift Sources/MemeFinderApp/MemeFinderApp.swift
git commit -m "feat: add cancel button for in-progress indexing"
```

---

## Self-Review

**Spec coverage:**
- §3.1 ThumbnailLoader (memory+disk, ImageIO downsample, cache key, nil on failure) → Tasks 1, 2 ✓
- §3.2 AsyncThumbnail async load → Task 3 ✓
- §3.3 Indexer parallel (cap 4, order, progress, errors, cancellation) → Task 5 ✓
- §3.4 429 backoff retry (max 3, exponential) → Task 5 (`retryingOnRateLimit`) ✓
- §3.5 LiveGeminiService status mapping + new error cases → Task 4 ✓
- §3.6 cancel UI (IndexingController/SettingsView/App) → Task 6 ✓
- §6 tests (cacheKey, ThumbnailLoader, mapResponse, indexer parallel/cap/retry, no regressions) → Tasks 1,2,4,5 ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. Task 6 Step 3 names the exact closure but defers property names to those already in the file (a deliberate accommodation, with explicit instruction not to change their creation).

**Type consistency:** `thumbnailCacheKey(path:modifiedAt:maxPixelSize:)`, `downsampledPNGData(path:maxPixelSize:)`, `ThumbnailLoader.thumbnailData(path:modifiedAt:maxPixelSize:)`, `ThumbnailLoader.shared`, `GeminiError.{rateLimited,httpError}`, `LiveGeminiService.mapResponse(data:statusCode:)`, `Indexer.init(service:maxConcurrent:retryBaseDelay:)`, `IndexOutcome.{index,errors}` are used identically across tasks. The `buildIndex` and `reindex` signatures are unchanged, so existing tests/callers stay valid. ✓
