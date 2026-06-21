import Foundation
import AppKit

public enum ClipboardError: Error, Equatable { case unreadable }

public protocol ClipboardWriter {
    func copyImage(at url: URL) throws
}

public struct AppKitClipboardWriter: ClipboardWriter {
    private let pasteboard: NSPasteboard
    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    public func copyImage(at url: URL) throws {
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
            throw ClipboardError.unreadable
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([image]) else { throw ClipboardError.unreadable }
    }
}
