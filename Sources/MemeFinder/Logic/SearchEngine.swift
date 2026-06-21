import Foundation

public struct SearchEngine {
    public init() {}

    public func search(queryEmbedding: [Float], queryText: String,
                       in images: [IndexedImage], limit: Int) -> [SearchResult] {
        let tokens = queryText.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let results: [SearchResult] = images.compactMap { image in
            let cos = cosineSimilarity(queryEmbedding, image.embedding)
            let haystack = (image.ocrText + " " + image.tags.joined(separator: " ")).lowercased()
            let matches = tokens.filter { !$0.isEmpty && haystack.contains($0) }.count
            let boost = 0.1 * Float(min(matches, 3))
            let score = cos + boost
            return score > 0 ? SearchResult(image: image, score: score) : nil
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }
}
