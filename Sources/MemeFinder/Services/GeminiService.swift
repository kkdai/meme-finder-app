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
