import Foundation

// Namespace marker used by the smoke test; real helpers added in Task 2.
public enum MemeFinder {
    public static let buildTag = "ok"
}

public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard !a.isEmpty, a.count == b.count else { return 0 }
    var dot: Float = 0, na: Float = 0, nb: Float = 0
    for i in 0..<a.count {
        dot += a[i] * b[i]
        na += a[i] * a[i]
        nb += b[i] * b[i]
    }
    guard na > 0, nb > 0 else { return 0 }
    return dot / (na.squareRoot() * nb.squareRoot())
}
