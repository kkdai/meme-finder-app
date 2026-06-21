import Testing
import Foundation
@testable import MemeFinder

@Test func identicalVectorsScoreOne() {
    let v: [Float] = [1, 2, 3]
    #expect(abs(cosineSimilarity(v, v) - 1.0) < 1e-5)
}

@Test func orthogonalVectorsScoreZero() {
    #expect(abs(cosineSimilarity([1, 0], [0, 1])) < 1e-5)
}

@Test func mismatchedLengthScoresZero() {
    #expect(cosineSimilarity([1, 2, 3], [1, 2]) == 0)
}

@Test func emptyOrZeroVectorScoresZero() {
    #expect(cosineSimilarity([], []) == 0)
    #expect(cosineSimilarity([0, 0], [1, 1]) == 0)
}
