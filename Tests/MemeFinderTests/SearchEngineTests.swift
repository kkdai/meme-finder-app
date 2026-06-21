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
    #expect(r.count == 2)                       // "c" (orthogonal -> score 0) excluded
    #expect(r[0].score > r[1].score)
}

@Test func keywordMatchBoostsScore() {
    let images = [img("a", [0, 1], tags: ["貓"]), img("b", [0, 1], ocr: "無關")]
    let r = SearchEngine().search(queryEmbedding: [1, 0], queryText: "貓", in: images, limit: 10)
    #expect(r.first?.image.id == "a")
    #expect((r.first?.score ?? 0) > 0)
    #expect(r.count == 1)
    #expect(abs((r.first?.score ?? 0) - 0.1) < 1e-6)
}

@Test func respectsLimit() {
    let images = (0..<5).map { img("\($0)", [1, 0]) }
    #expect(SearchEngine().search(queryEmbedding: [1, 0], queryText: "", in: images, limit: 2).count == 2)
}
