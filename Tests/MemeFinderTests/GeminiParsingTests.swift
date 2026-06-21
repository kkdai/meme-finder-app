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
