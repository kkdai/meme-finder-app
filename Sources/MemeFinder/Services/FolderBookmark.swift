import Foundation

public struct FolderBookmark {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "memeFolderBookmark") {
        self.defaults = defaults; self.key = key
    }

    public func store(_ url: URL) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope],
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: key)
    }

    public func resolve() -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return url
    }
}
