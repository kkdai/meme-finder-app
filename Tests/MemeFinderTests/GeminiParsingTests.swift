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

@Test func parsesAnnotationSkippingThoughtPart() throws {
    // A thinking model can return a leading part with no text (a "thought"),
    // followed by the real JSON part. The parser must skip to the text part.
    let json = """
    {"candidates":[{"content":{"parts":[
      {"thoughtSignature":"abc"},
      {"text":"{\\"ocr_text\\":\\"嗨\\",\\"description\\":\\"狗\\",\\"tags\\":[\\"狗\\"],\\"emotion\\":\\"開心\\"}"}
    ]}}]}
    """
    let a = try GeminiParsing.annotation(fromGenerateContent: Data(json.utf8))
    #expect(a == Annotation(ocrText: "嗨", description: "狗", tags: ["狗"], emotion: "開心"))
}

@Test func throwsOnMalformedResponse() {
    #expect(throws: GeminiError.self) {
        _ = try GeminiParsing.annotation(fromGenerateContent: Data("{}".utf8))
    }
}

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

@Test func liveServiceThrowsMissingKeyWhenEmpty() async {
    let svc = LiveGeminiService(keyProvider: { "" })
    await #expect(throws: GeminiError.missingKey) { _ = try await svc.embed(text: "x") }
}

@Test func mapResponseHandlesStatusCodes() throws {
    #expect(try LiveGeminiService.mapResponse(data: Data([1, 2]), statusCode: 200) == Data([1, 2]))
    #expect(throws: GeminiError.rateLimited) {
        _ = try LiveGeminiService.mapResponse(data: Data(), statusCode: 429)
    }
    #expect(throws: GeminiError.httpError(500)) {
        _ = try LiveGeminiService.mapResponse(data: Data(), statusCode: 500)
    }
}
