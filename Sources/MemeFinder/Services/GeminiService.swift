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
