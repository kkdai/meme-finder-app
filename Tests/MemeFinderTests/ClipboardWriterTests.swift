import Testing
import Foundation
import AppKit
@testable import MemeFinder

@Test func writesImageToPasteboard() throws {
    // Build a tiny valid PNG on disk.
    let img = NSImage(size: NSSize(width: 2, height: 2))
    img.lockFocus(); NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2)); img.unlockFocus()
    let tiff = img.tiffRepresentation!
    let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
    try png.write(to: url)

    let pb = NSPasteboard(name: NSPasteboard.Name("MemeFinderTestPB"))
    try AppKitClipboardWriter(pasteboard: pb).copyImage(at: url)
    #expect(NSImage(pasteboard: pb) != nil)
}

@Test func throwsOnUnreadableFile() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
    try? Data("not an image".utf8).write(to: url)
    let pb = NSPasteboard(name: NSPasteboard.Name("MemeFinderTestPB2"))
    #expect(throws: ClipboardError.self) {
        try AppKitClipboardWriter(pasteboard: pb).copyImage(at: url)
    }
}
