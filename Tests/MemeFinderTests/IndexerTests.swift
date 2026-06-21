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

private final class ConcurrencyService: GeminiService, @unchecked Sendable {
    let lock = NSLock()
    var current = 0
    var peak = 0
    func annotate(imageData: Data, mimeType: String) async throws -> Annotation {
        lock.withLock { current += 1; peak = max(peak, current) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        lock.withLock { current -= 1 }
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
        let n = lock.withLock { embedCalls += 1; return embedCalls }
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
