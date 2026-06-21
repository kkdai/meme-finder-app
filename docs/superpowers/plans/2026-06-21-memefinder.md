# MemeFinder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native SwiftUI macOS app where the user picks a local meme folder, Gemini auto-indexes each image (OCR text, description, tags, emotion + a semantic embedding), and typing a Chinese query shows ranked memes that copy to the clipboard on click.

**Architecture:** A Swift Package Manager executable (SwiftUI + AppKit) — no full Xcode required. Pure-logic units (vector math, search ranking, index persistence, Gemini JSON parsing, indexer) are isolated behind protocols so they unit-test without touching the network or the filesystem permission system. SwiftUI views are thin shells over testable view models. The app is packaged into `MemeFinder.app` by a build script.

**Tech Stack:** Swift 6.3 toolchain, Swift Package Manager, SwiftUI, AppKit (`NSPasteboard`), Swift Testing (`import Testing`), Gemini REST API (`gemini-3-flash-preview` for vision, `gemini-embedding-2` for embeddings).

## Global Constraints

- Swift tools version floor: `// swift-tools-version:6.0`; platform floor `.macOS(.v14)`.
- App is **not** sandboxed (run directly / packaged `.app`); no entitlements file is needed for network or filesystem access.
- All Gemini access goes through the `GeminiService` protocol; tests MUST mock it and MUST NOT call the live API.
- Gemini models (exact strings): vision = `gemini-3-flash-preview`; embeddings = `gemini-embedding-2`. Never use `gemini-1.5-*` / `gemini-2.0-*`.
- Gemini REST base: `https://generativelanguage.googleapis.com/v1beta/models/{model}:{method}`, auth header `x-goog-api-key: <key>`.
- Embedding output dimensionality: `768` (request field `output_dimensionality`). Response vector path: `embeddings[0].values`.
- Supported image extensions (lowercased): `jpg`, `jpeg`, `png`, `webp`.
- API key stored in macOS Keychain via `SecretStore`; never written to disk in plaintext or logged.
- Test framework: Swift Testing (`import Testing`, `@Test`, `#expect`). Run with `swift test`.
- Commit after every task with a `feat:`/`test:`/`chore:` prefixed message.

---

## File Structure

```
Package.swift
Sources/MemeFinder/
  MemeFinderApp.swift            # @main App entry, wires views
  Models/
    IndexedImage.swift           # Codable record per image (metadata + embedding)
    MemeIndex.swift              # collection + JSON load/save with corruption recovery
    SearchResult.swift           # image + score
  Logic/
    Vector.swift                 # cosineSimilarity (pure)
    SearchEngine.swift           # ranking: cosine + keyword boost (pure)
    GeminiParsing.swift          # parse generateContent / embedContent JSON (pure)
    Indexer.swift                # scan folder, incremental, call GeminiService
  Services/
    GeminiService.swift          # protocol + Annotation type + live REST impl
    ClipboardWriter.swift        # protocol + AppKit NSPasteboard impl
    SecretStore.swift            # protocol + Keychain impl + in-memory impl
    FolderBookmark.swift         # security-scoped bookmark store/resolve
  ViewModels/
    SettingsViewModel.swift
    SearchViewModel.swift
  Views/
    ContentView.swift
    SettingsView.swift
    ResultGridView.swift
Tests/MemeFinderTests/
  VectorTests.swift
  MemeIndexTests.swift
  SearchEngineTests.swift
  GeminiParsingTests.swift
  IndexerTests.swift
  ClipboardWriterTests.swift
  SecretStoreTests.swift
  FolderBookmarkTests.swift
  SettingsViewModelTests.swift
  SearchViewModelTests.swift
  Fixtures/
    generate_content.json
    embed_content.json
build-app.sh                     # packages release binary into MemeFinder.app
```

---

### Task 1: Project scaffolding (SwiftPM executable + test target)

**Files:**
- Create: `Package.swift`
- Create: `Sources/MemeFinder/Logic/Vector.swift` (placeholder so the target compiles)
- Test: `Tests/MemeFinderTests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable package named `MemeFinder` with an executable target `MemeFinder` and a test target `MemeFinderTests`; confirms `swift test` runs Swift Testing.

- [ ] **Step 1: Write the failing test**

`Tests/MemeFinderTests/SmokeTests.swift`:
```swift
import Testing
@testable import MemeFinder

@Test func packageBuildsAndTestsRun() {
    #expect(MemeFinder.buildTag == "ok")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test 2>&1 | tail -20`
Expected: FAIL — `buildTag` / type `MemeFinder` not found (compile error).

- [ ] **Step 3: Write Package.swift and minimal source**

`Package.swift`:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MemeFinder",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MemeFinder",
            path: "Sources/MemeFinder"
        ),
        .testTarget(
            name: "MemeFinderTests",
            dependencies: ["MemeFinder"],
            path: "Tests/MemeFinderTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

`Sources/MemeFinder/Logic/Vector.swift`:
```swift
import Foundation

// Namespace marker used by the smoke test; real helpers added in Task 2.
public enum MemeFinder {
    public static let buildTag = "ok"
}
```

Create the fixtures dir so the resource copy succeeds:
```bash
mkdir -p Tests/MemeFinderTests/Fixtures
echo '{}' > Tests/MemeFinderTests/Fixtures/.keep
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test 2>&1 | tail -20`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: scaffold SwiftPM package with Swift Testing"
```

---

### Task 2: Cosine similarity (pure vector math)

**Files:**
- Modify: `Sources/MemeFinder/Logic/Vector.swift`
- Test: `Tests/MemeFinderTests/VectorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float` — returns 0 when either vector is empty, mismatched length, or zero-magnitude; otherwise dot / (|a||b|).

- [ ] **Step 1: Write the failing test**

`Tests/MemeFinderTests/VectorTests.swift`:
```swift
import Testing
import Foundation
@testable import MemeFinder

@Test func identicalVectorsScoreOne() {
    let v: [Float] = [1, 2, 3]
    #expect(abs(cosineSimilarity(v, v) - 1.0) < 1e-5)
}

@Test func orthogonalVectorsScoreZero() {
    #expect(abs(cosineSimilarity([1, 0], [0, 1])) < 1e-5)
}

@Test func mismatchedLengthScoresZero() {
    #expect(cosineSimilarity([1, 2, 3], [1, 2]) == 0)
}

@Test func emptyOrZeroVectorScoresZero() {
    #expect(cosineSimilarity([], []) == 0)
    #expect(cosineSimilarity([0, 0], [1, 1]) == 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VectorTests 2>&1 | tail -20`
Expected: FAIL — `cosineSimilarity` not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/MemeFinder/Logic/Vector.swift`:
```swift
public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard !a.isEmpty, a.count == b.count else { return 0 }
    var dot: Float = 0, na: Float = 0, nb: Float = 0
    for i in 0..<a.count {
        dot += a[i] * b[i]
        na += a[i] * a[i]
        nb += b[i] * b[i]
    }
    guard na > 0, nb > 0 else { return 0 }
    return dot / (na.squareRoot() * nb.squareRoot())
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter VectorTests 2>&1 | tail -20`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/Logic/Vector.swift Tests/MemeFinderTests/VectorTests.swift
git commit -m "feat: add cosine similarity helper"
```

---

### Task 3: IndexedImage model + MemeIndex persistence

**Files:**
- Create: `Sources/MemeFinder/Models/IndexedImage.swift`
- Create: `Sources/MemeFinder/Models/MemeIndex.swift`
- Test: `Tests/MemeFinderTests/MemeIndexTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct IndexedImage: Codable, Identifiable, Equatable { var id: String; var path: String; var modifiedAt: Date; var ocrText: String; var imageDescription: String; var tags: [String]; var emotion: String; var embedding: [Float] }` (`id` equals `path`).
  - `struct MemeIndex: Codable, Equatable { var images: [IndexedImage]; init(images: [IndexedImage] = []) }`
  - `static func MemeIndex.load(from url: URL) -> MemeIndex` — returns empty index if file missing OR corrupt (never throws).
  - `func MemeIndex.save(to url: URL) throws` — writes JSON, creating parent dirs.

- [ ] **Step 1: Write the failing test**

`Tests/MemeFinderTests/MemeIndexTests.swift`:
```swift
import Testing
import Foundation
@testable import MemeFinder

private func tmpFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("index.json")
}

private func sample() -> IndexedImage {
    IndexedImage(id: "/m/a.png", path: "/m/a.png", modifiedAt: Date(timeIntervalSince1970: 100),
                 ocrText: "好棒", imageDescription: "貓咪比讚", tags: ["貓", "讚"],
                 emotion: "開心", embedding: [0.1, 0.2, 0.3])
}

@Test func saveThenLoadRoundTrips() throws {
    let url = tmpFile()
    var idx = MemeIndex()
    idx.images.append(sample())
    try idx.save(to: url)
    let loaded = MemeIndex.load(from: url)
    #expect(loaded == idx)
}

@Test func loadMissingFileReturnsEmpty() {
    #expect(MemeIndex.load(from: tmpFile()).images.isEmpty)
}

@Test func loadCorruptFileReturnsEmpty() throws {
    let url = tmpFile()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "{ not json".data(using: .utf8)!.write(to: url)
    #expect(MemeIndex.load(from: url).images.isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MemeIndexTests 2>&1 | tail -20`
Expected: FAIL — `IndexedImage` / `MemeIndex` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/MemeFinder/Models/IndexedImage.swift`:
```swift
import Foundation

public struct IndexedImage: Codable, Identifiable, Equatable {
    public var id: String
    public var path: String
    public var modifiedAt: Date
    public var ocrText: String
    public var imageDescription: String
    public var tags: [String]
    public var emotion: String
    public var embedding: [Float]

    public init(id: String, path: String, modifiedAt: Date, ocrText: String,
                imageDescription: String, tags: [String], emotion: String, embedding: [Float]) {
        self.id = id; self.path = path; self.modifiedAt = modifiedAt
        self.ocrText = ocrText; self.imageDescription = imageDescription
        self.tags = tags; self.emotion = emotion; self.embedding = embedding
    }
}
```

`Sources/MemeFinder/Models/MemeIndex.swift`:
```swift
import Foundation

public struct MemeIndex: Codable, Equatable {
    public var images: [IndexedImage]
    public init(images: [IndexedImage] = []) { self.images = images }

    public static func load(from url: URL) -> MemeIndex {
        guard let data = try? Data(contentsOf: url),
              let idx = try? JSONDecoder().decode(MemeIndex.self, from: data) else {
            return MemeIndex()
        }
        return idx
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MemeIndexTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/Models Tests/MemeFinderTests/MemeIndexTests.swift
git commit -m "feat: add IndexedImage model and MemeIndex JSON persistence"
```

---

### Task 4: SearchEngine (cosine + keyword boost ranking)

**Files:**
- Create: `Sources/MemeFinder/Models/SearchResult.swift`
- Create: `Sources/MemeFinder/Logic/SearchEngine.swift`
- Test: `Tests/MemeFinderTests/SearchEngineTests.swift`

**Interfaces:**
- Consumes: `IndexedImage`, `cosineSimilarity`.
- Produces:
  - `struct SearchResult: Identifiable, Equatable { var image: IndexedImage; var score: Float; var id: String { image.id } }`
  - `struct SearchEngine { init(); func search(queryEmbedding: [Float], queryText: String, in images: [IndexedImage], limit: Int) -> [SearchResult] }`
  - Scoring: `score = cosineSimilarity(queryEmbedding, image.embedding) + keywordBoost`, where `keywordBoost = 0.1 * Float(min(matches, 3))` and `matches` counts whitespace-separated, lowercased query tokens that appear as a substring of `ocrText` or any tag (case-insensitive). Results sorted by score descending, truncated to `limit`. Images with score `<= 0` are excluded.

- [ ] **Step 1: Write the failing test**

`Tests/MemeFinderTests/SearchEngineTests.swift`:
```swift
import Testing
import Foundation
@testable import MemeFinder

private func img(_ id: String, _ emb: [Float], ocr: String = "", tags: [String] = []) -> IndexedImage {
    IndexedImage(id: id, path: id, modifiedAt: Date(), ocrText: ocr,
                 imageDescription: "", tags: tags, emotion: "", embedding: emb)
}

@Test func ranksByCosineDescending() {
    let images = [img("a", [1, 0]), img("b", [0.7, 0.7]), img("c", [0, 1])]
    let r = SearchEngine().search(queryEmbedding: [1, 0], queryText: "", in: images, limit: 10)
    #expect(r.map(\.image.id) == ["a", "b"])  // "c" is orthogonal -> score 0, excluded
}

@Test func keywordMatchBoostsScore() {
    let images = [img("a", [0, 1], tags: ["貓"]), img("b", [0, 1], ocr: "無關")]
    let r = SearchEngine().search(queryEmbedding: [1, 0], queryText: "貓", in: images, limit: 10)
    #expect(r.first?.image.id == "a")
    #expect((r.first?.score ?? 0) > 0)
}

@Test func respectsLimit() {
    let images = (0..<5).map { img("\($0)", [1, 0]) }
    #expect(SearchEngine().search(queryEmbedding: [1, 0], queryText: "", in: images, limit: 2).count == 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SearchEngineTests 2>&1 | tail -20`
Expected: FAIL — `SearchEngine` / `SearchResult` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/MemeFinder/Models/SearchResult.swift`:
```swift
import Foundation

public struct SearchResult: Identifiable, Equatable {
    public var image: IndexedImage
    public var score: Float
    public var id: String { image.id }
    public init(image: IndexedImage, score: Float) { self.image = image; self.score = score }
}
```

`Sources/MemeFinder/Logic/SearchEngine.swift`:
```swift
import Foundation

public struct SearchEngine {
    public init() {}

    public func search(queryEmbedding: [Float], queryText: String,
                       in images: [IndexedImage], limit: Int) -> [SearchResult] {
        let tokens = queryText.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let results: [SearchResult] = images.compactMap { image in
            let cos = cosineSimilarity(queryEmbedding, image.embedding)
            let haystack = (image.ocrText + " " + image.tags.joined(separator: " ")).lowercased()
            let matches = tokens.filter { !$0.isEmpty && haystack.contains($0) }.count
            let boost = 0.1 * Float(min(matches, 3))
            let score = cos + boost
            return score > 0 ? SearchResult(image: image, score: score) : nil
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SearchEngineTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/Models/SearchResult.swift Sources/MemeFinder/Logic/SearchEngine.swift Tests/MemeFinderTests/SearchEngineTests.swift
git commit -m "feat: add search engine with cosine + keyword ranking"
```

---

### Task 5: Gemini JSON parsing (pure, no network)

**Files:**
- Create: `Sources/MemeFinder/Services/GeminiService.swift` (protocol + `Annotation` only in this task)
- Create: `Sources/MemeFinder/Logic/GeminiParsing.swift`
- Create: `Tests/MemeFinderTests/Fixtures/generate_content.json`
- Create: `Tests/MemeFinderTests/Fixtures/embed_content.json`
- Test: `Tests/MemeFinderTests/GeminiParsingTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct Annotation: Equatable { var ocrText: String; var description: String; var tags: [String]; var emotion: String }`
  - `protocol GeminiService: Sendable { func annotate(imageData: Data, mimeType: String) async throws -> Annotation; func embed(text: String) async throws -> [Float] }`
  - `enum GeminiParsing { static func annotation(fromGenerateContent data: Data) throws -> Annotation; static func embedding(fromEmbedContent data: Data) throws -> [Float] }`
  - `enum GeminiError: Error { case badResponse(String) }`
  - The vision call requests `responseMimeType: application/json`; the model returns a JSON string inside `candidates[0].content.parts[0].text` whose object is `{ "ocr_text", "description", "tags":[], "emotion" }`. The embedding response vector is at `embeddings[0].values`.

- [ ] **Step 1: Write the failing test + fixtures**

`Tests/MemeFinderTests/Fixtures/generate_content.json`:
```json
{
  "candidates": [
    {
      "content": {
        "parts": [
          { "text": "{\"ocr_text\":\"你好\",\"description\":\"一隻貓比讚\",\"tags\":[\"貓\",\"讚\"],\"emotion\":\"開心\"}" }
        ]
      }
    }
  ]
}
```

`Tests/MemeFinderTests/Fixtures/embed_content.json`:
```json
{ "embeddings": [ { "values": [0.01, 0.02, 0.03] } ] }
```

`Tests/MemeFinderTests/GeminiParsingTests.swift`:
```swift
import Testing
import Foundation
@testable import MemeFinder

private func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
    return try Data(contentsOf: url)
}

@Test func parsesAnnotationFromGenerateContent() throws {
    let a = try GeminiParsing.annotation(fromGenerateContent: fixture("generate_content"))
    #expect(a == Annotation(ocrText: "你好", description: "一隻貓比讚", tags: ["貓", "讚"], emotion: "開心"))
}

@Test func parsesEmbeddingValues() throws {
    let v = try GeminiParsing.embedding(fromEmbedContent: fixture("embed_content"))
    #expect(v == [0.01, 0.02, 0.03])
}

@Test func throwsOnMalformedResponse() {
    #expect(throws: GeminiError.self) {
        _ = try GeminiParsing.annotation(fromGenerateContent: Data("{}".utf8))
    }
}
```

Remove the placeholder keep-file so it isn't bundled noise:
```bash
rm -f Tests/MemeFinderTests/Fixtures/.keep
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GeminiParsingTests 2>&1 | tail -20`
Expected: FAIL — `GeminiParsing` / `Annotation` / `GeminiError` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/MemeFinder/Services/GeminiService.swift`:
```swift
import Foundation

public struct Annotation: Equatable, Sendable {
    public var ocrText: String
    public var description: String
    public var tags: [String]
    public var emotion: String
    public init(ocrText: String, description: String, tags: [String], emotion: String) {
        self.ocrText = ocrText; self.description = description
        self.tags = tags; self.emotion = emotion
    }
}

public enum GeminiError: Error, Equatable {
    case badResponse(String)
}

public protocol GeminiService: Sendable {
    func annotate(imageData: Data, mimeType: String) async throws -> Annotation
    func embed(text: String) async throws -> [Float]
}
```

`Sources/MemeFinder/Logic/GeminiParsing.swift`:
```swift
import Foundation

public enum GeminiParsing {
    public static func annotation(fromGenerateContent data: Data) throws -> Annotation {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String,
            let inner = text.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: inner) as? [String: Any]
        else { throw GeminiError.badResponse("cannot parse generateContent payload") }

        return Annotation(
            ocrText: obj["ocr_text"] as? String ?? "",
            description: obj["description"] as? String ?? "",
            tags: obj["tags"] as? [String] ?? [],
            emotion: obj["emotion"] as? String ?? ""
        )
    }

    public static func embedding(fromEmbedContent data: Data) throws -> [Float] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let embeddings = root["embeddings"] as? [[String: Any]],
            let values = embeddings.first?["values"] as? [Double]
        else { throw GeminiError.badResponse("cannot parse embedContent payload") }
        return values.map(Float.init)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GeminiParsingTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/Services/GeminiService.swift Sources/MemeFinder/Logic/GeminiParsing.swift Tests/MemeFinderTests/GeminiParsingTests.swift Tests/MemeFinderTests/Fixtures
git commit -m "feat: add Gemini protocol and response parsing"
```

---

### Task 6: Live Gemini REST client

**Files:**
- Modify: `Sources/MemeFinder/Services/GeminiService.swift` (add `LiveGeminiService`)
- Test: `Tests/MemeFinderTests/GeminiParsingTests.swift` (add request-building test)

**Interfaces:**
- Consumes: `GeminiService`, `GeminiParsing`, `Annotation`.
- Produces:
  - `struct LiveGeminiService: GeminiService { init(apiKey: String, session: URLSession = .shared) }` conforming to the protocol via REST.
  - `static func LiveGeminiService.annotateRequest(apiKey: String, imageData: Data, mimeType: String) -> URLRequest` and `static func LiveGeminiService.embedRequest(apiKey: String, text: String) -> URLRequest` — pure builders so the URL, headers, and body are unit-testable without a network call.

- [ ] **Step 1: Write the failing test**

Append to `Tests/MemeFinderTests/GeminiParsingTests.swift`:
```swift
@Test func annotateRequestIsWellFormed() throws {
    let req = LiveGeminiService.annotateRequest(apiKey: "K", imageData: Data([1, 2, 3]), mimeType: "image/png")
    #expect(req.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent")
    #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "K")
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    let gc = body["generationConfig"] as! [String: Any]
    #expect(gc["responseMimeType"] as? String == "application/json")
}

@Test func embedRequestIsWellFormed() throws {
    let req = LiveGeminiService.embedRequest(apiKey: "K", text: "貓")
    #expect(req.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-2:embedContent")
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    #expect(body["output_dimensionality"] as? Int == 768)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GeminiParsingTests 2>&1 | tail -20`
Expected: FAIL — `LiveGeminiService` not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/MemeFinder/Services/GeminiService.swift`:
```swift
public struct LiveGeminiService: GeminiService {
    private let apiKey: String
    private let session: URLSession
    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey; self.session = session
    }

    private static let base = "https://generativelanguage.googleapis.com/v1beta/models"

    public static func annotateRequest(apiKey: String, imageData: Data, mimeType: String) -> URLRequest {
        let prompt = """
        你是迷因圖標註助手。請閱讀這張圖，輸出 JSON，欄位：
        ocr_text(圖中所有文字), description(用繁體中文描述畫面與梗),
        tags(3-8 個繁體中文關鍵字陣列), emotion(單一情緒詞)。只輸出 JSON。
        """
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": mimeType, "data": imageData.base64EncodedString()]]
                ]
            ]],
            "generationConfig": ["responseMimeType": "application/json"]
        ]
        var req = URLRequest(url: URL(string: "\(base)/gemini-3-flash-preview:generateContent")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    public static func embedRequest(apiKey: String, text: String) -> URLRequest {
        let body: [String: Any] = [
            "content": ["parts": [["text": text]]],
            "output_dimensionality": 768
        ]
        var req = URLRequest(url: URL(string: "\(base)/gemini-embedding-2:embedContent")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    public func annotate(imageData: Data, mimeType: String) async throws -> Annotation {
        let (data, _) = try await session.data(for: Self.annotateRequest(apiKey: apiKey, imageData: imageData, mimeType: mimeType))
        return try GeminiParsing.annotation(fromGenerateContent: data)
    }

    public func embed(text: String) async throws -> [Float] {
        let (data, _) = try await session.data(for: Self.embedRequest(apiKey: apiKey, text: text))
        return try GeminiParsing.embedding(fromEmbedContent: data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GeminiParsingTests 2>&1 | tail -20`
Expected: PASS (5 tests in file).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/Services/GeminiService.swift Tests/MemeFinderTests/GeminiParsingTests.swift
git commit -m "feat: add live Gemini REST client with testable request builders"
```

---

### Task 7: Indexer (incremental folder scan)

**Files:**
- Create: `Sources/MemeFinder/Logic/Indexer.swift`
- Test: `Tests/MemeFinderTests/IndexerTests.swift`

**Interfaces:**
- Consumes: `GeminiService`, `Annotation`, `IndexedImage`, `MemeIndex`.
- Produces:
  - `struct IndexError: Equatable { var path: String; var message: String }`
  - `struct IndexOutcome { var index: MemeIndex; var errors: [IndexError] }`
  - `struct Indexer { init(service: GeminiService); func buildIndex(folder: URL, existing: MemeIndex, progress: @Sendable (Int, Int) -> Void) async -> IndexOutcome }`
  - Behavior: enumerate files in `folder` whose lowercased extension is in {jpg,jpeg,png,webp}; for each, if `existing` already has an `IndexedImage` with the same `path` and equal `modifiedAt`, reuse it (skip Gemini); otherwise call `annotate` + `embed`, build a new `IndexedImage`. On any thrown error for a file, record an `IndexError` and continue. `progress(done, total)` fires once per file. mimeType derived from extension (`jpg`/`jpeg`→`image/jpeg`, `png`→`image/png`, `webp`→`image/webp`).

- [ ] **Step 1: Write the failing test**

`Tests/MemeFinderTests/IndexerTests.swift`:
```swift
import Testing
import Foundation
@testable import MemeFinder

final class FakeService: GeminiService, @unchecked Sendable {
    var annotateCalls = 0
    func annotate(imageData: Data, mimeType: String) async throws -> Annotation {
        annotateCalls += 1
        return Annotation(ocrText: "T", description: "D", tags: ["x"], emotion: "E")
    }
    func embed(text: String) async throws -> [Float] { [0.5, 0.5] }
}

private func makeFolder(_ names: [String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for n in names { try Data([0]).write(to: dir.appendingPathComponent(n)) }
    return dir
}

@Test func indexesSupportedImagesAndSkipsOthers() async throws {
    let dir = try makeFolder(["a.png", "b.jpg", "notes.txt"])
    let svc = FakeService()
    let out = await Indexer(service: svc).buildIndex(folder: dir, existing: MemeIndex()) { _, _ in }
    #expect(out.index.images.count == 2)
    #expect(svc.annotateCalls == 2)
    #expect(out.errors.isEmpty)
}

@Test func reusesUnchangedEntriesWithoutCallingGemini() async throws {
    let dir = try makeFolder(["a.png"])
    let path = dir.appendingPathComponent("a.png").path
    let mtime = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as! Date
    let existing = MemeIndex(images: [IndexedImage(id: path, path: path, modifiedAt: mtime,
        ocrText: "old", imageDescription: "", tags: [], emotion: "", embedding: [1])])
    let svc = FakeService()
    let out = await Indexer(service: svc).buildIndex(folder: dir, existing: existing) { _, _ in }
    #expect(svc.annotateCalls == 0)
    #expect(out.index.images.first?.ocrText == "old")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter IndexerTests 2>&1 | tail -20`
Expected: FAIL — `Indexer` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/MemeFinder/Logic/Indexer.swift`:
```swift
import Foundation

public struct IndexError: Equatable, Sendable { public var path: String; public var message: String }
public struct IndexOutcome: Sendable { public var index: MemeIndex; public var errors: [IndexError] }

public struct Indexer {
    private static let exts: Set<String> = ["jpg", "jpeg", "png", "webp"]
    private let service: GeminiService
    public init(service: GeminiService) { self.service = service }

    private func mimeType(for ext: String) -> String {
        switch ext { case "png": return "image/png"; case "webp": return "image/webp"; default: return "image/jpeg" }
    }

    public func buildIndex(folder: URL, existing: MemeIndex,
                           progress: @Sendable (Int, Int) -> Void) async -> IndexOutcome {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { Self.exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path }
        let byPath = Dictionary(uniqueKeysWithValues: existing.images.map { ($0.path, $0) })

        var images: [IndexedImage] = []
        var errors: [IndexError] = []
        for (i, url) in files.enumerated() {
            let path = url.path
            let mtime = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil ?? Date()
            if let prev = byPath[path], prev.modifiedAt == mtime {
                images.append(prev)
            } else {
                do {
                    let data = try Data(contentsOf: url)
                    let mime = mimeType(for: url.pathExtension.lowercased())
                    let ann = try await service.annotate(imageData: data, mimeType: mime)
                    let embedText = [ann.ocrText, ann.description, ann.tags.joined(separator: " "), ann.emotion].joined(separator: " ")
                    let vec = try await service.embed(text: embedText)
                    images.append(IndexedImage(id: path, path: path, modifiedAt: mtime,
                        ocrText: ann.ocrText, imageDescription: ann.description,
                        tags: ann.tags, emotion: ann.emotion, embedding: vec))
                } catch {
                    errors.append(IndexError(path: path, message: String(describing: error)))
                }
            }
            progress(i + 1, files.count)
        }
        return IndexOutcome(index: MemeIndex(images: images), errors: errors)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter IndexerTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/Logic/Indexer.swift Tests/MemeFinderTests/IndexerTests.swift
git commit -m "feat: add incremental folder indexer"
```

---

### Task 8: ClipboardWriter

**Files:**
- Create: `Sources/MemeFinder/Services/ClipboardWriter.swift`
- Test: `Tests/MemeFinderTests/ClipboardWriterTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `protocol ClipboardWriter { func copyImage(at url: URL) throws }`
  - `enum ClipboardError: Error { case unreadable }`
  - `struct AppKitClipboardWriter: ClipboardWriter { init(pasteboard: NSPasteboard = .general); func copyImage(at url: URL) throws }` — reads the file into an `NSImage`, clears the pasteboard, and writes the image; throws `.unreadable` if the file is not a valid image.

- [ ] **Step 1: Write the failing test**

`Tests/MemeFinderTests/ClipboardWriterTests.swift`:
```swift
import Testing
import Foundation
import AppKit
@testable import MemeFinder

@Test func writesImageToPasteboard() throws {
    // Build a tiny valid PNG on disk.
    let img = NSImage(size: NSSize(width: 2, height: 2))
    img.lockFocus(); NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2)); img.unlockFocus()
    let tiff = img.tiffRepresentation!
    let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
    try png.write(to: url)

    let pb = NSPasteboard(name: NSPasteboard.Name("MemeFinderTestPB"))
    try AppKitClipboardWriter(pasteboard: pb).copyImage(at: url)
    #expect(NSImage(pasteboard: pb) != nil)
}

@Test func throwsOnUnreadableFile() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
    try? Data("not an image".utf8).write(to: url)
    let pb = NSPasteboard(name: NSPasteboard.Name("MemeFinderTestPB2"))
    #expect(throws: ClipboardError.self) {
        try AppKitClipboardWriter(pasteboard: pb).copyImage(at: url)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipboardWriterTests 2>&1 | tail -20`
Expected: FAIL — `AppKitClipboardWriter` / `ClipboardError` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/MemeFinder/Services/ClipboardWriter.swift`:
```swift
import Foundation
import AppKit

public enum ClipboardError: Error, Equatable { case unreadable }

public protocol ClipboardWriter {
    func copyImage(at url: URL) throws
}

public struct AppKitClipboardWriter: ClipboardWriter {
    private let pasteboard: NSPasteboard
    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    public func copyImage(at url: URL) throws {
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
            throw ClipboardError.unreadable
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([image]) else { throw ClipboardError.unreadable }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ClipboardWriterTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/Services/ClipboardWriter.swift Tests/MemeFinderTests/ClipboardWriterTests.swift
git commit -m "feat: add clipboard writer for image copy"
```

---

### Task 9: SecretStore (API key) + FolderBookmark

**Files:**
- Create: `Sources/MemeFinder/Services/SecretStore.swift`
- Create: `Sources/MemeFinder/Services/FolderBookmark.swift`
- Test: `Tests/MemeFinderTests/SecretStoreTests.swift`
- Test: `Tests/MemeFinderTests/FolderBookmarkTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `protocol SecretStore: AnyObject { func setAPIKey(_ key: String); func apiKey() -> String? }`
  - `final class InMemorySecretStore: SecretStore` (for tests + previews).
  - `final class KeychainSecretStore: SecretStore { init(account: String = "gemini-api-key") }` using `Security` generic-password items.
  - `struct FolderBookmark { init(defaults: UserDefaults = .standard, key: String = "memeFolderBookmark"); func store(_ url: URL) throws; func resolve() -> URL? }` using `URL.bookmarkData()` / `URL(resolvingBookmarkData:)`.

- [ ] **Step 1: Write the failing test**

`Tests/MemeFinderTests/SecretStoreTests.swift`:
```swift
import Testing
@testable import MemeFinder

@Test func inMemoryStoreRoundTrips() {
    let s = InMemorySecretStore()
    #expect(s.apiKey() == nil)
    s.setAPIKey("ABC")
    #expect(s.apiKey() == "ABC")
}
```

`Tests/MemeFinderTests/FolderBookmarkTests.swift`:
```swift
import Testing
import Foundation
@testable import MemeFinder

@Test func bookmarkRoundTripsAFolder() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let defaults = UserDefaults(suiteName: "memefinder.test.\(UUID().uuidString)")!
    let bm = FolderBookmark(defaults: defaults, key: "k")
    #expect(bm.resolve() == nil)
    try bm.store(dir)
    #expect(bm.resolve()?.standardizedFileURL == dir.standardizedFileURL)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SecretStoreTests 2>&1 | tail -20 && swift test --filter FolderBookmarkTests 2>&1 | tail -20`
Expected: FAIL — types not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/MemeFinder/Services/SecretStore.swift`:
```swift
import Foundation
import Security

public protocol SecretStore: AnyObject {
    func setAPIKey(_ key: String)
    func apiKey() -> String?
}

public final class InMemorySecretStore: SecretStore {
    private var value: String?
    public init() {}
    public func setAPIKey(_ key: String) { value = key }
    public func apiKey() -> String? { value }
}

public final class KeychainSecretStore: SecretStore {
    private let account: String
    public init(account: String = "gemini-api-key") { self.account = account }

    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "MemeFinder",
         kSecAttrAccount as String: account]
    }

    public func setAPIKey(_ key: String) {
        SecItemDelete(baseQuery() as CFDictionary)
        var q = baseQuery()
        q[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    public func apiKey() -> String? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

`Sources/MemeFinder/Services/FolderBookmark.swift`:
```swift
import Foundation

public struct FolderBookmark {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "memeFolderBookmark") {
        self.defaults = defaults; self.key = key
    }

    public func store(_ url: URL) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope],
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: key)
    }

    public func resolve() -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return url
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SecretStoreTests 2>&1 | tail -20 && swift test --filter FolderBookmarkTests 2>&1 | tail -20`
Expected: PASS. (Note: only `InMemorySecretStore` is unit-tested; `KeychainSecretStore` is verified manually in Task 12 because Keychain access is unreliable under the SPM test runner.)

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/Services/SecretStore.swift Sources/MemeFinder/Services/FolderBookmark.swift Tests/MemeFinderTests/SecretStoreTests.swift Tests/MemeFinderTests/FolderBookmarkTests.swift
git commit -m "feat: add Keychain secret store and folder bookmark"
```

---

### Task 10: SettingsViewModel

**Files:**
- Create: `Sources/MemeFinder/ViewModels/SettingsViewModel.swift`
- Test: `Tests/MemeFinderTests/SettingsViewModelTests.swift`

**Interfaces:**
- Consumes: `SecretStore`, `FolderBookmark`.
- Produces:
  - `@MainActor final class SettingsViewModel: ObservableObject { @Published var maskedKey: String; @Published var folderPath: String?; init(secrets: SecretStore, bookmark: FolderBookmark); func saveAPIKey(_ raw: String); func setFolder(_ url: URL); var hasAPIKey: Bool }`
  - `saveAPIKey` trims whitespace, stores via `SecretStore`, and updates `maskedKey` to a masked form (`••••` + last 4 chars, or empty if blank). `setFolder` stores the bookmark and updates `folderPath`. On init, load existing key/folder to populate published state.

- [ ] **Step 1: Write the failing test**

`Tests/MemeFinderTests/SettingsViewModelTests.swift`:
```swift
import Testing
import Foundation
@testable import MemeFinder

@MainActor
@Test func savingKeyMasksAndPersists() {
    let secrets = InMemorySecretStore()
    let vm = SettingsViewModel(secrets: secrets,
                               bookmark: FolderBookmark(defaults: UserDefaults(suiteName: "t.\(UUID())")!, key: "k"))
    vm.saveAPIKey("  SECRET1234  ")
    #expect(secrets.apiKey() == "SECRET1234")
    #expect(vm.maskedKey == "••••1234")
    #expect(vm.hasAPIKey)
}

@MainActor
@Test func loadsExistingKeyOnInit() {
    let secrets = InMemorySecretStore()
    secrets.setAPIKey("ABCD9999")
    let vm = SettingsViewModel(secrets: secrets,
                               bookmark: FolderBookmark(defaults: UserDefaults(suiteName: "t.\(UUID())")!, key: "k"))
    #expect(vm.maskedKey == "••••9999")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsViewModelTests 2>&1 | tail -20`
Expected: FAIL — `SettingsViewModel` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/MemeFinder/ViewModels/SettingsViewModel.swift`:
```swift
import Foundation
import SwiftUI

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var maskedKey: String = ""
    @Published public var folderPath: String?

    private let secrets: SecretStore
    private let bookmark: FolderBookmark

    public init(secrets: SecretStore, bookmark: FolderBookmark) {
        self.secrets = secrets
        self.bookmark = bookmark
        self.maskedKey = Self.mask(secrets.apiKey())
        self.folderPath = bookmark.resolve()?.path
    }

    public var hasAPIKey: Bool { (secrets.apiKey()?.isEmpty == false) }

    public func saveAPIKey(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        secrets.setAPIKey(trimmed)
        maskedKey = Self.mask(trimmed)
    }

    public func setFolder(_ url: URL) {
        try? bookmark.store(url)
        folderPath = url.path
    }

    private static func mask(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "" }
        return "••••" + String(key.suffix(4))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SettingsViewModelTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/ViewModels/SettingsViewModel.swift Tests/MemeFinderTests/SettingsViewModelTests.swift
git commit -m "feat: add settings view model"
```

---

### Task 11: SearchViewModel

**Files:**
- Create: `Sources/MemeFinder/ViewModels/SearchViewModel.swift`
- Test: `Tests/MemeFinderTests/SearchViewModelTests.swift`

**Interfaces:**
- Consumes: `GeminiService`, `SearchEngine`, `MemeIndex`, `SearchResult`, `ClipboardWriter`.
- Produces:
  - `@MainActor final class SearchViewModel: ObservableObject { @Published var query: String; @Published var results: [SearchResult]; @Published var errorMessage: String?; init(service: GeminiService, clipboard: ClipboardWriter, index: MemeIndex, engine: SearchEngine = SearchEngine(), limit: Int = 30); func runSearch() async; func copy(_ result: SearchResult) }`
  - `runSearch`: blank query clears results; otherwise embeds the query via `service.embed`, runs `engine.search`, assigns `results`; on thrown error sets `errorMessage`. `copy` calls `clipboard.copyImage(at:)` with the result's path URL and sets `errorMessage` on failure.

- [ ] **Step 1: Write the failing test**

`Tests/MemeFinderTests/SearchViewModelTests.swift`:
```swift
import Testing
import Foundation
@testable import MemeFinder

private final class StubService: GeminiService, @unchecked Sendable {
    func annotate(imageData: Data, mimeType: String) async throws -> Annotation {
        Annotation(ocrText: "", description: "", tags: [], emotion: "")
    }
    func embed(text: String) async throws -> [Float] { [1, 0] }
}

private final class SpyClipboard: ClipboardWriter, @unchecked Sendable {
    var copied: [URL] = []
    func copyImage(at url: URL) throws { copied.append(url) }
}

@MainActor
@Test func runSearchPopulatesRankedResults() async {
    let index = MemeIndex(images: [
        IndexedImage(id: "/m/a.png", path: "/m/a.png", modifiedAt: Date(), ocrText: "", imageDescription: "",
                     tags: [], emotion: "", embedding: [1, 0]),
        IndexedImage(id: "/m/b.png", path: "/m/b.png", modifiedAt: Date(), ocrText: "", imageDescription: "",
                     tags: [], emotion: "", embedding: [0, 1]),
    ])
    let vm = SearchViewModel(service: StubService(), clipboard: SpyClipboard(), index: index)
    vm.query = "貓"
    await vm.runSearch()
    #expect(vm.results.map(\.image.id) == ["/m/a.png"])
}

@MainActor
@Test func blankQueryClearsResults() async {
    let vm = SearchViewModel(service: StubService(), clipboard: SpyClipboard(), index: MemeIndex())
    vm.query = "   "
    await vm.runSearch()
    #expect(vm.results.isEmpty)
}

@MainActor
@Test func copyDelegatesToClipboard() {
    let clip = SpyClipboard()
    let vm = SearchViewModel(service: StubService(), clipboard: clip, index: MemeIndex())
    let r = SearchResult(image: IndexedImage(id: "/m/a.png", path: "/m/a.png", modifiedAt: Date(),
        ocrText: "", imageDescription: "", tags: [], emotion: "", embedding: [1]), score: 1)
    vm.copy(r)
    #expect(clip.copied.map(\.path) == ["/m/a.png"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SearchViewModelTests 2>&1 | tail -20`
Expected: FAIL — `SearchViewModel` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/MemeFinder/ViewModels/SearchViewModel.swift`:
```swift
import Foundation
import SwiftUI

@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public var query: String = ""
    @Published public var results: [SearchResult] = []
    @Published public var errorMessage: String?

    private let service: GeminiService
    private let clipboard: ClipboardWriter
    private let index: MemeIndex
    private let engine: SearchEngine
    private let limit: Int

    public init(service: GeminiService, clipboard: ClipboardWriter, index: MemeIndex,
                engine: SearchEngine = SearchEngine(), limit: Int = 30) {
        self.service = service; self.clipboard = clipboard; self.index = index
        self.engine = engine; self.limit = limit
    }

    public func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; return }
        do {
            let vec = try await service.embed(text: q)
            results = engine.search(queryEmbedding: vec, queryText: q, in: index.images, limit: limit)
            errorMessage = nil
        } catch {
            errorMessage = "搜尋失敗：\(error.localizedDescription)"
        }
    }

    public func copy(_ result: SearchResult) {
        do { try clipboard.copyImage(at: URL(fileURLWithPath: result.image.path)) }
        catch { errorMessage = "複製失敗" }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SearchViewModelTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MemeFinder/ViewModels/SearchViewModel.swift Tests/MemeFinderTests/SearchViewModelTests.swift
git commit -m "feat: add search view model"
```

---

### Task 12: SwiftUI views, app entry, and build script

**Files:**
- Create: `Sources/MemeFinder/Views/ResultGridView.swift`
- Create: `Sources/MemeFinder/Views/SettingsView.swift`
- Create: `Sources/MemeFinder/Views/ContentView.swift`
- Create: `Sources/MemeFinder/MemeFinderApp.swift`
- Create: `build-app.sh`
- Test: full-suite run + manual launch (no new unit test; views are thin and exercised manually)

**Interfaces:**
- Consumes: `SearchViewModel`, `SettingsViewModel`, `KeychainSecretStore`, `FolderBookmark`, `LiveGeminiService`, `AppKitClipboardWriter`, `MemeIndex`, `Indexer`.
- Produces: a runnable `MemeFinder.app`.

This task wires already-tested units into SwiftUI. Logic stays in the view models; views only render and forward events.

- [ ] **Step 1: Write the result grid view**

`Sources/MemeFinder/Views/ResultGridView.swift`:
```swift
import SwiftUI

public struct ResultGridView: View {
    public let results: [SearchResult]
    public let onTap: (SearchResult) -> Void
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    public init(results: [SearchResult], onTap: @escaping (SearchResult) -> Void) {
        self.results = results; self.onTap = onTap
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(results) { r in
                    Button { onTap(r) } label: {
                        AsyncThumbnail(path: r.image.path)
                    }
                    .buttonStyle(.plain)
                    .help("點一下複製到剪貼簿")
                }
            }
            .padding()
        }
    }
}

struct AsyncThumbnail: View {
    let path: String
    var body: some View {
        Group {
            if let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 2: Write the settings view**

`Sources/MemeFinder/Views/SettingsView.swift`:
```swift
import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var keyField: String = ""
    public init(vm: SettingsViewModel) { self.vm = vm }

    public var body: some View {
        Form {
            Section("Gemini API 金鑰") {
                HStack {
                    SecureField("貼上 API 金鑰", text: $keyField)
                    Button("儲存") { vm.saveAPIKey(keyField); keyField = "" }
                }
                if !vm.maskedKey.isEmpty { Text("目前：\(vm.maskedKey)").foregroundStyle(.secondary) }
            }
            Section("迷因資料夾") {
                HStack {
                    Text(vm.folderPath ?? "尚未選擇").foregroundStyle(.secondary)
                    Spacer()
                    Button("選擇資料夾…") { chooseFolder() }
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { vm.setFolder(url) }
    }
}
```

- [ ] **Step 3: Write the content view**

`Sources/MemeFinder/Views/ContentView.swift`:
```swift
import SwiftUI

public struct ContentView: View {
    @ObservedObject var vm: SearchViewModel
    @State private var copiedID: String?
    public init(vm: SearchViewModel) { self.vm = vm }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜尋迷因…例如：謝謝、無言、好棒", text: $vm.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await vm.runSearch() } }
                Button("搜尋") { Task { await vm.runSearch() } }
            }
            .padding()

            if let msg = vm.errorMessage {
                Text(msg).foregroundStyle(.red).padding(.horizontal)
            }
            if let id = copiedID {
                Text("已複製 ✓").foregroundStyle(.green).padding(.horizontal).id(id)
            }

            ResultGridView(results: vm.results) { r in
                vm.copy(r)
                copiedID = r.id
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
```

- [ ] **Step 4: Write the app entry**

`Sources/MemeFinder/MemeFinderApp.swift`:
```swift
import SwiftUI

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
```

- [ ] **Step 5: Run the full test suite**

Run: `swift test 2>&1 | tail -25`
Expected: PASS — all tests across all files green.

- [ ] **Step 6: Write the build script**

`build-app.sh`:
```bash
#!/bin/bash
set -euo pipefail
APP="MemeFinder.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/MemeFinder"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MemeFinder"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MemeFinder</string>
  <key>CFBundleDisplayName</key><string>MemeFinder</string>
  <key>CFBundleIdentifier</key><string>com.local.memefinder</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>MemeFinder</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
echo "Built $APP"
```

Make it executable:
```bash
chmod +x build-app.sh
```

- [ ] **Step 7: Build and verify the app bundle launches**

Run:
```bash
./build-app.sh && plutil -lint MemeFinder.app/Contents/Info.plist && open MemeFinder.app
```
Expected: script prints `Built MemeFinder.app`, `plutil` reports `OK`, and the app window opens with a search box. Manually verify: open Settings (Cmd-,), paste a Gemini key, pick a meme folder, then confirm search returns results and clicking a result copies the image (paste into Notes/Messages). This is also where `KeychainSecretStore` is verified end-to-end.

- [ ] **Step 8: Commit**

```bash
git add Sources/MemeFinder/Views Sources/MemeFinder/MemeFinderApp.swift build-app.sh
git commit -m "feat: add SwiftUI views, app entry, and app bundle build script"
```

---

### Task 13: First-run indexing trigger + roadmap docs

**Files:**
- Modify: `Sources/MemeFinder/Views/SettingsView.swift` (add "重新索引" button + progress)
- Create: `Sources/MemeFinder/ViewModels/IndexingController.swift`
- Create: `docs/01_plan/project-roadmap.md`
- Test: `Tests/MemeFinderTests/IndexingControllerTests.swift`

**Interfaces:**
- Consumes: `Indexer`, `GeminiService`, `MemeIndex`, `FolderBookmark`.
- Produces:
  - `@MainActor final class IndexingController: ObservableObject { @Published var progress: Double; @Published var statusText: String; init(service: GeminiService, indexURL: URL); func reindex(folder: URL, existing: MemeIndex) async -> MemeIndex }`
  - `reindex` runs the `Indexer`, updates `progress` (0...1) and `statusText` from the progress callback, saves the resulting index to `indexURL`, and returns it. Errors are summarized into `statusText`.

- [ ] **Step 1: Write the failing test**

`Tests/MemeFinderTests/IndexingControllerTests.swift`:
```swift
import Testing
import Foundation
@testable import MemeFinder

private final class OKService: GeminiService, @unchecked Sendable {
    func annotate(imageData: Data, mimeType: String) async throws -> Annotation {
        Annotation(ocrText: "t", description: "d", tags: ["x"], emotion: "e")
    }
    func embed(text: String) async throws -> [Float] { [0.1, 0.2] }
}

@MainActor
@Test func reindexBuildsSavesAndReportsProgress() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data([0]).write(to: dir.appendingPathComponent("a.png"))
    let indexURL = dir.appendingPathComponent("index.json")

    let controller = IndexingController(service: OKService(), indexURL: indexURL)
    let result = await controller.reindex(folder: dir, existing: MemeIndex())

    #expect(result.images.count == 1)
    #expect(controller.progress == 1.0)
    #expect(MemeIndex.load(from: indexURL).images.count == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter IndexingControllerTests 2>&1 | tail -20`
Expected: FAIL — `IndexingController` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/MemeFinder/ViewModels/IndexingController.swift`:
```swift
import Foundation
import SwiftUI

@MainActor
public final class IndexingController: ObservableObject {
    @Published public var progress: Double = 0
    @Published public var statusText: String = ""
    private let service: GeminiService
    private let indexURL: URL

    public init(service: GeminiService, indexURL: URL) {
        self.service = service; self.indexURL = indexURL
    }

    public func reindex(folder: URL, existing: MemeIndex) async -> MemeIndex {
        statusText = "索引中…"
        let outcome = await Indexer(service: service).buildIndex(folder: folder, existing: existing) { done, total in
            Task { @MainActor in
                self.progress = total == 0 ? 1 : Double(done) / Double(total)
                self.statusText = "索引中… \(done)/\(total)"
            }
        }
        progress = 1.0
        try? outcome.index.save(to: indexURL)
        statusText = outcome.errors.isEmpty ? "索引完成（\(outcome.index.images.count) 張）"
                                            : "完成，但有 \(outcome.errors.count) 張失敗"
        return outcome.index
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter IndexingControllerTests 2>&1 | tail -20`
Expected: PASS (1 test).

- [ ] **Step 5: Wire the reindex button into SettingsView**

Add to `SettingsView` (inside the `迷因資料夾` section, below the folder row). Requires passing an `IndexingController` and the current folder/index in; add stored properties `let onReindex: () -> Void` to `SettingsView.init` and call it from a button:
```swift
                Button("重新索引") { onReindex() }
                    .disabled(vm.folderPath == nil || !vm.hasAPIKey)
```
Update `SettingsView.init` to accept `onReindex: @escaping () -> Void` and store it, and update the `Settings { ... }` scene in `MemeFinderApp` to supply a closure that calls a new `IndexingController.reindex(folder:existing:)` using the resolved bookmark folder, then reloads `search`'s index (re-create the `SearchViewModel` index by reading `MemeIndex.load(from: indexURL)`).

Run: `swift build 2>&1 | tail -10`
Expected: builds cleanly.

- [ ] **Step 6: Write roadmap doc**

`docs/01_plan/project-roadmap.md`:
```markdown
# MemeFinder — Project Roadmap

## Status: V1 complete (local-only)

## Done
- Native SwiftUI macOS app (SwiftPM build, no Xcode required)
- Gemini vision auto-tagging + embeddings indexing of a local meme folder
- Semantic + keyword search, click-to-copy to clipboard
- Settings: Gemini API key (Keychain) + folder picker + reindex

## Next (V2)
- Online source fallback (Tenor, Gemini-ecosystem)
- Global hotkey / menu-bar mode
- Reverse image search

See design: docs/superpowers/specs/2026-06-21-memefinder-design.md
```

- [ ] **Step 7: Run full suite and commit**

```bash
swift test 2>&1 | tail -25
git add Sources docs
git commit -m "feat: add reindex controller, settings trigger, and roadmap"
```

---

## Self-Review

**Spec coverage:**
- §3.1 Settings (folder + Keychain key) → Tasks 9, 10, 12, 13 ✓
- §3.2 Indexer (incremental, Gemini vision + embed) → Tasks 5, 6, 7, 13 ✓
- §3.3 Search (embed query, cosine + keyword) → Tasks 2, 4, 11 ✓
- §3.4 Results grid (lazy thumbnails) → Task 12 ✓
- §3.5 Clipboard copy → Tasks 8, 11, 12 ✓
- §5 hybrid search strategy → Task 4 ✓
- §6 storage (Keychain / bookmark / JSON) → Tasks 3, 9 ✓
- §7 error handling (missing key, network fail continues, unreadable skip, empty results) → Tasks 7, 8, 11 ✓
- §8 testing (parsing, cosine, ranking, persistence, incremental skip, clipboard, mocked Gemini) → Tasks 2–11, 13 ✓
- §9 SwiftPM build into .app → Tasks 1, 12 ✓

**Placeholder scan:** No TBD/TODO; every code step contains complete code. Task 13 Step 5 describes a wiring change in prose but specifies exact added code, the new init parameter, and the build verification command.

**Type consistency:** `GeminiService.embed(text:)`/`annotate(imageData:mimeType:)`, `Annotation` field names (`ocrText`,`description`,`tags`,`emotion`), `IndexedImage` fields (`imageDescription` not `description`), `SearchEngine.search(queryEmbedding:queryText:in:limit:)`, `SearchResult.{image,score}`, `MemeIndex.{load(from:),save(to:),images}`, `ClipboardWriter.copyImage(at:)`, `SecretStore.{setAPIKey,apiKey}`, `FolderBookmark.{store,resolve}` are used identically across all consuming tasks. ✓
