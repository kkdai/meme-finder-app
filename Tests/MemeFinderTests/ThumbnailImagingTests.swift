import Testing
import Foundation
import AppKit
@testable import MemeFinder

@Test func cacheKeyIsStableAndSensitive() {
    let d = Date(timeIntervalSince1970: 100)
    let a = thumbnailCacheKey(path: "/x.png", modifiedAt: d, maxPixelSize: 280)
    #expect(a == thumbnailCacheKey(path: "/x.png", modifiedAt: d, maxPixelSize: 280))
    #expect(a.count == 64)
    #expect(a != thumbnailCacheKey(path: "/x.png", modifiedAt: d, maxPixelSize: 281))
    #expect(a != thumbnailCacheKey(path: "/x.png", modifiedAt: Date(timeIntervalSince1970: 101), maxPixelSize: 280))
    #expect(a != thumbnailCacheKey(path: "/y.png", modifiedAt: d, maxPixelSize: 280))
}

private func writePNG(_ side: Int) throws -> URL {
    let img = NSImage(size: NSSize(width: side, height: side))
    img.lockFocus(); NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: side, height: side)); img.unlockFocus()
    let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
    try png.write(to: url)
    return url
}

@Test func downsampleProducesSmallerImage() throws {
    let url = try writePNG(200)
    let data = try #require(downsampledPNGData(path: url.path, maxPixelSize: 64))
    let rep = try #require(NSBitmapImageRep(data: data))
    #expect(max(rep.pixelsWide, rep.pixelsHigh) <= 64)
    #expect(rep.pixelsWide > 0)
}

@Test func downsampleReturnsNilForNonImage() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
    try Data("not an image".utf8).write(to: url)
    #expect(downsampledPNGData(path: url.path, maxPixelSize: 64) == nil)
}
