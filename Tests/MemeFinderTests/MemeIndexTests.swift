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
