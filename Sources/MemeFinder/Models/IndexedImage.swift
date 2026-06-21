import Foundation

public struct IndexedImage: Codable, Identifiable, Equatable {
    public var id: String
    public var path: String
    public var modifiedAt: Date
    public var ocrText: String
    public var imageDescription: String
    public var tags: [String]
    public var emotion: String
    public var embedding: [Float]

    public init(id: String, path: String, modifiedAt: Date, ocrText: String,
                imageDescription: String, tags: [String], emotion: String, embedding: [Float]) {
        self.id = id; self.path = path; self.modifiedAt = modifiedAt
        self.ocrText = ocrText; self.imageDescription = imageDescription
        self.tags = tags; self.emotion = emotion; self.embedding = embedding
    }
}
