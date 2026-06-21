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
        self.results = allImagesNewestFirst()
    }

    /// All indexed images as results, newest first (by file modification date).
    /// Used as the default browse view before any search is run.
    private func allImagesNewestFirst() -> [SearchResult] {
        index.images
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .map { SearchResult(image: $0, score: 0) }
    }

    /// Reset the grid to show every indexed image, newest first.
    public func showAll() {
        results = allImagesNewestFirst()
        errorMessage = nil
    }

    public func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = allImagesNewestFirst(); return }
        do {
            let vec = try await service.embed(text: q)
            results = engine.search(queryEmbedding: vec, queryText: q, in: index.images, limit: limit)
            errorMessage = nil
        } catch GeminiError.missingKey {
            errorMessage = "請先到設定（⌘,）輸入 Gemini API 金鑰"
        } catch {
            errorMessage = "搜尋失敗：\(error.localizedDescription)"
        }
    }

    public func updateIndex(_ index: MemeIndex) {
        self.index = index
        results = allImagesNewestFirst()
    }

    public func copy(_ result: SearchResult) {
        do { try clipboard.copyImage(at: URL(fileURLWithPath: result.image.path)) }
        catch { errorMessage = "複製失敗" }
    }
}
