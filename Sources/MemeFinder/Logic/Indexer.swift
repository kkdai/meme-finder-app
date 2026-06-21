import Foundation

public struct IndexError: Equatable, Sendable { public var path: String; public var message: String }
public struct IndexOutcome: Sendable { public var index: MemeIndex; public var errors: [IndexError] }

public struct Indexer {
    private static let exts: Set<String> = ["jpg", "jpeg", "png", "webp"]
    private let service: GeminiService
    public init(service: GeminiService) { self.service = service }

    private func mimeType(for ext: String) -> String {
        switch ext { case "png": return "image/png"; case "webp": return "image/webp"; default: return "image/jpeg" }
    }

    public func buildIndex(folder: URL, existing: MemeIndex,
                           progress: @Sendable (Int, Int) -> Void) async -> IndexOutcome {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { Self.exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path }
        let normalize = { (path: String) -> String in (NSURL(fileURLWithPath: path) as URL).standardizedFileURL.path }
        let byPath = Dictionary(uniqueKeysWithValues: existing.images.map { (normalize($0.path), $0) })

        var images: [IndexedImage] = []
        var errors: [IndexError] = []
        for (i, url) in files.enumerated() {
            let path = normalize(url.path)
            let mtime = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil ?? Date()
            if let prev = byPath[path], prev.modifiedAt == mtime {
                images.append(prev)
            } else {
                do {
                    let data = try Data(contentsOf: url)
                    let mime = mimeType(for: url.pathExtension.lowercased())
                    let ann = try await service.annotate(imageData: data, mimeType: mime)
                    let embedText = [ann.ocrText, ann.description, ann.tags.joined(separator: " "), ann.emotion].joined(separator: " ")
                    let vec = try await service.embed(text: embedText)
                    images.append(IndexedImage(id: path, path: path, modifiedAt: mtime,
                        ocrText: ann.ocrText, imageDescription: ann.description,
                        tags: ann.tags, emotion: ann.emotion, embedding: vec))
                } catch {
                    errors.append(IndexError(path: path, message: String(describing: error)))
                }
            }
            progress(i + 1, files.count)
        }
        return IndexOutcome(index: MemeIndex(images: images), errors: errors)
    }
}
