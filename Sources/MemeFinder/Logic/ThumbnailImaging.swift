import Foundation
import CryptoKit
import ImageIO
import AppKit

public func thumbnailCacheKey(path: String, modifiedAt: Date, maxPixelSize: Int) -> String {
    let input = "\(path)|\(modifiedAt.timeIntervalSince1970)|\(maxPixelSize)"
    return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
}

public func downsampledPNGData(path: String, maxPixelSize: Int) -> Data? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
}
