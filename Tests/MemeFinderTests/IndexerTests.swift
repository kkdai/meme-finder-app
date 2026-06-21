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
