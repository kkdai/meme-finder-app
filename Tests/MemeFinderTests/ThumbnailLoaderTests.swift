import Testing
import Foundation
import AppKit
@testable import MemeFinder

private func writePNG(_ side: Int) throws -> (URL, Date) {
    let img = NSImage(size: NSSize(width: side, height: side))
    img.lockFocus(); NSColor.blue.drawSwatch(in: NSRect(x: 0, y: 0, width: side, height: side)); img.unlockFocus()
    let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
    try png.write(to: url)
    let mtime = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date
    return (url, mtime)
}

@Test func loaderGeneratesCachesToDiskAndReturnsSameData() async throws {
    let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let loader = ThumbnailLoader(diskDirectory: cacheDir)
    let (url, mtime) = try writePNG(200)

    let d1 = try #require(await loader.thumbnailData(path: url.path, modifiedAt: mtime, maxPixelSize: 64))
    let key = thumbnailCacheKey(path: url.path, modifiedAt: mtime, maxPixelSize: 64)
    #expect(FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent(key + ".png").path))

    let d2 = await loader.thumbnailData(path: url.path, modifiedAt: mtime, maxPixelSize: 64)
    #expect(d2 == d1)  // served from cache, identical bytes
}

@Test func loaderReturnsNilForMissingFile() async {
    let loader = ThumbnailLoader(diskDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let data = await loader.thumbnailData(path: "/nope/missing.png", modifiedAt: Date(), maxPixelSize: 64)
    #expect(data == nil)
}
