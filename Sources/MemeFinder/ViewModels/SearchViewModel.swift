import Foundation
import Combine

@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public var query: String = ""
    @Published public var results: [SearchResult] = []
    @Published public var errorMessage: String?

    private let service: GeminiService
    private let clipboard: ClipboardWriter
    private var index: MemeIndex
    private let engine: SearchEngine
    private let limit: Int

    public init(service: GeminiService, clipboard: ClipboardWriter, index: MemeIndex,
                engine: SearchEngine = SearchEngine(), limit: Int = 30) {
        self.service = service; self.clipboard = clipboard; self.index = index
        self.engine = engine; self.limit = limit
    }

    public func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; return }
        do {
            let vec = try await service.embed(text: q)
            results = engine.search(queryEmbedding: vec, queryText: q, in: index.images, limit: limit)
            errorMessage = nil
        } catch {
            errorMessage = "搜尋失敗：\(error.localizedDescription)"
        }
    }

    public func updateIndex(_ index: MemeIndex) { self.index = index }

    public func copy(_ result: SearchResult) {
        do { try clipboard.copyImage(at: URL(fileURLWithPath: result.image.path)) }
        catch { errorMessage = "複製失敗" }
    }
}
