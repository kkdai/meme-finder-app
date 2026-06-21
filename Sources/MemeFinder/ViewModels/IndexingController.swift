import Foundation
import Combine

@MainActor
public final class IndexingController: ObservableObject {
    @Published public var progress: Double = 0
    @Published public var statusText: String = ""
    private let service: GeminiService
    private let indexURL: URL

    public init(service: GeminiService, indexURL: URL) {
        self.service = service; self.indexURL = indexURL
    }

    public func reindex(folder: URL, existing: MemeIndex) async -> MemeIndex {
        statusText = "索引中…"
        let outcome = await Indexer(service: service).buildIndex(folder: folder, existing: existing) { done, total in
            Task { @MainActor in
                self.progress = total == 0 ? 1 : Double(done) / Double(total)
                self.statusText = "索引中… \(done)/\(total)"
            }
        }
        progress = 1.0
        try? outcome.index.save(to: indexURL)
        statusText = outcome.errors.isEmpty ? "索引完成（\(outcome.index.images.count) 張）"
                                            : "完成，但有 \(outcome.errors.count) 張失敗"
        return outcome.index
    }
}
