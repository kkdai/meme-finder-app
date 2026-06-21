import Testing
import Foundation
@testable import MemeFinder

@Test func bookmarkRoundTripsAFolder() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let defaults = UserDefaults(suiteName: "memefinder.test.\(UUID().uuidString)")!
    let bm = FolderBookmark(defaults: defaults, key: "k")
    #expect(bm.resolve() == nil)
    try bm.store(dir)
    #expect(bm.resolve()?.standardizedFileURL == dir.standardizedFileURL)
}
