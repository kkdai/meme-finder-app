import Foundation

public enum GeminiParsing {
    public static func annotation(fromGenerateContent data: Data) throws -> Annotation {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            // A thinking model can emit a separate "thought" part with no text;
            // take the first part that actually carries text.
            let text = parts.compactMap({ $0["text"] as? String }).first(where: { !$0.isEmpty }),
            let inner = text.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: inner) as? [String: Any]
        else { throw GeminiError.badResponse("cannot parse generateContent payload") }

        return Annotation(
            ocrText: obj["ocr_text"] as? String ?? "",
            description: obj["description"] as? String ?? "",
            tags: obj["tags"] as? [String] ?? [],
            emotion: obj["emotion"] as? String ?? ""
        )
    }

    public static func embedding(fromEmbedContent data: Data) throws -> [Float] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.badResponse("cannot parse embedContent payload")
        }
        // The single embedContent endpoint returns {"embedding":{"values":[...]}}.
        if let embedding = root["embedding"] as? [String: Any],
           let values = embedding["values"] as? [Double] {
            return values.map(Float.init)
        }
        // batchEmbedContents would return {"embeddings":[{"values":[...]}]} — tolerate it.
        if let embeddings = root["embeddings"] as? [[String: Any]],
           let values = embeddings.first?["values"] as? [Double] {
            return values.map(Float.init)
        }
        throw GeminiError.badResponse("cannot parse embedContent payload")
    }
}
