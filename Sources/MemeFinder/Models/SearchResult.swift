import Foundation

public struct SearchResult: Identifiable, Equatable {
    public var image: IndexedImage
    public var score: Float
    public var id: String { image.id }
    public init(image: IndexedImage, score: Float) { self.image = image; self.score = score }
}
