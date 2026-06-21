import Foundation

public actor ThumbnailLoader {
    private let diskDirectory: URL
    private let memory = NSCache<NSString, NSData>()

    public init(diskDirectory: URL? = nil, memoryCountLimit: Int = 300) {
        self.diskDirectory = diskDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MemeFinder/thumbnails")
        memory.countLimit = memoryCountLimit
        try? FileManager.default.createDirectory(at: self.diskDirectory, withIntermediateDirectories: true)
    }

    public func thumbnailData(path: String, modifiedAt: Date, maxPixelSize: Int) -> Data? {
        let key = thumbnailCacheKey(path: path, modifiedAt: modifiedAt, maxPixelSize: maxPixelSize)
        let nsKey = key as NSString
        if let cached = memory.object(forKey: nsKey) { return cached as Data }

        let diskURL = diskDirectory.appendingPathComponent(key + ".png")
        if let onDisk = try? Data(contentsOf: diskURL) {
            memory.setObject(onDisk as NSData, forKey: nsKey)
            return onDisk
        }

        guard let data = downsampledPNGData(path: path, maxPixelSize: maxPixelSize) else { return nil }
        memory.setObject(data as NSData, forKey: nsKey)
        try? data.write(to: diskURL)
        return data
    }
}

extension ThumbnailLoader {
    public static let shared = ThumbnailLoader()
}
