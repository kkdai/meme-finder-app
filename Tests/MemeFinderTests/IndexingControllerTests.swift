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
