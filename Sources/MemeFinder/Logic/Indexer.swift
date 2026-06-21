import Foundation

public struct IndexError: Equatable, Sendable { public var path: String; public var message: String }
public struct IndexOutcome: Sendable { public var index: MemeIndex; public var errors: [IndexError] }

public struct Indexer: Sendable {
    private static let exts: Set<String> = ["jpg", "jpeg", "png", "webp"]
    private let service: GeminiService
    private let maxConcurrent: Int
    private let retryBaseDelay: Double

    public init(service: GeminiService, maxConcurrent: Int = 4, retryBaseDelay: Double = 0.5) {
        self.service = service
        self.maxConcurrent = max(1, maxConcurrent)
        self.retryBaseDelay = retryBaseDelay
    }

    private func mimeType(for ext: String) -> String {
        switch ext { case "png": return "image/png"; case "webp": return "image/webp"; default: return "image/jpeg" }
    }

    private struct WorkResult: Sendable {
        let path: String
        let image: IndexedImage?
        let error: IndexError?
    }

    private func retryingOnRateLimit<T: Sendable>(_ op: @Sendable () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do { return try await op() }
            catch GeminiError.rateLimited {
                attempt += 1
                if attempt >= 3 { throw GeminiError.rateLimited }
                let delay = retryBaseDelay * pow(2.0, Double(attempt - 1))
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            }
        }
    }

    public func buildIndex(folder: URL, existing: MemeIndex,
                           progress: @Sendable (Int, Int) -> Void) async -> IndexOutcome {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { Self.exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.standardizedFileURL.path < $1.standardizedFileURL.path }
        let byPath = Dictionary(uniqueKeysWithValues: existing.images.map { ($0.path, $0) })
        let total = files.count

        var resultsByPath: [String: IndexedImage] = [:]
        var errors: [IndexError] = []
        var done = 0

        await withTaskGroup(of: WorkResult.self) { group in
            var iterator = files.makeIterator()

            func scheduleNext() -> Bool {
                guard !Task.isCancelled, let url = iterator.next() else { return false }
                let path = url.standardizedFileURL.path
                let mtime = ((try? fm.attributesOfItem(atPath: path)[.modificationDate]) as? Date) ?? Date()
                if let prev = byPath[path], prev.modifiedAt == mtime {
                    group.addTask { WorkResult(path: path, image: prev, error: nil) }
                    return true
                }
                let service = self.service
                let mime = mimeType(for: url.pathExtension.lowercased())
                group.addTask {
                    do {
                        let data = try Data(contentsOf: url)
                        let ann = try await self.retryingOnRateLimit { try await service.annotate(imageData: data, mimeType: mime) }
                        let text = [ann.ocrText, ann.description, ann.tags.joined(separator: " "), ann.emotion].joined(separator: " ")
                        let vec = try await self.retryingOnRateLimit { try await service.embed(text: text) }
                        let img = IndexedImage(id: path, path: path, modifiedAt: mtime,
                                               ocrText: ann.ocrText, imageDescription: ann.description,
                                               tags: ann.tags, emotion: ann.emotion, embedding: vec)
                        return WorkResult(path: path, image: img, error: nil)
                    } catch {
                        return WorkResult(path: path, image: nil,
                                          error: IndexError(path: path, message: String(describing: error)))
                    }
                }
                return true
            }

            for _ in 0..<maxConcurrent { if !scheduleNext() { break } }
            while let res = await group.next() {
                if let img = res.image { resultsByPath[res.path] = img }
                if let err = res.error { errors.append(err) }
                done += 1
                progress(done, total)
                _ = scheduleNext()
            }
        }

        let ordered = files.map { $0.standardizedFileURL.path }.compactMap { resultsByPath[$0] }
        return IndexOutcome(index: MemeIndex(images: ordered), errors: errors)
    }
}
