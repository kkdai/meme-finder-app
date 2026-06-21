import Foundation

public struct MemeIndex: Codable, Equatable {
    public var images: [IndexedImage]
    public init(images: [IndexedImage] = []) { self.images = images }

    public static func load(from url: URL) -> MemeIndex {
        guard let data = try? Data(contentsOf: url),
              let idx = try? JSONDecoder().decode(MemeIndex.self, from: data) else {
            return MemeIndex()
        }
        return idx
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
