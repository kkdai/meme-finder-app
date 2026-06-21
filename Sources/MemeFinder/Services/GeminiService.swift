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
    case missingKey
    case rateLimited
    case httpError(Int)
}

public protocol GeminiService: Sendable {
    func annotate(imageData: Data, mimeType: String) async throws -> Annotation
    func embed(text: String) async throws -> [Float]
}

public struct LiveGeminiService: GeminiService {
    private let keyProvider: @Sendable () -> String?
    private let session: URLSession
    public init(keyProvider: @escaping @Sendable () -> String?, session: URLSession = .shared) {
        self.keyProvider = keyProvider; self.session = session
    }
    public init(apiKey: String, session: URLSession = .shared) {
        let key = apiKey
        self.init(keyProvider: { key }, session: session)
    }

    private func currentKey() throws -> String {
        guard let k = keyProvider(), !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.missingKey
        }
        return k
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

    public static func mapResponse(data: Data, statusCode: Int) throws -> Data {
        switch statusCode {
        case 200...299: return data
        case 429: throw GeminiError.rateLimited
        default: throw GeminiError.httpError(statusCode)
        }
    }

    public func annotate(imageData: Data, mimeType: String) async throws -> Annotation {
        let key = try currentKey()
        let (data, resp) = try await session.data(for: Self.annotateRequest(apiKey: key, imageData: imageData, mimeType: mimeType))
        let checked = try Self.mapResponse(data: data, statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0)
        return try GeminiParsing.annotation(fromGenerateContent: checked)
    }

    public func embed(text: String) async throws -> [Float] {
        let key = try currentKey()
        let (data, resp) = try await session.data(for: Self.embedRequest(apiKey: key, text: text))
        let checked = try Self.mapResponse(data: data, statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0)
        return try GeminiParsing.embedding(fromEmbedContent: checked)
    }
}
