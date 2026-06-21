import Foundation
import Combine

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var maskedKey: String = ""
    @Published public var folderPath: String?

    private let secrets: SecretStore
    private let bookmark: FolderBookmark

    public init(secrets: SecretStore, bookmark: FolderBookmark) {
        self.secrets = secrets
        self.bookmark = bookmark
        self.maskedKey = Self.mask(secrets.apiKey())
        self.folderPath = bookmark.resolve()?.path
    }

    public var hasAPIKey: Bool { (secrets.apiKey()?.isEmpty == false) }

    public func saveAPIKey(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        secrets.setAPIKey(trimmed)
        maskedKey = Self.mask(trimmed)
    }

    public func setFolder(_ url: URL) {
        try? bookmark.store(url)
        folderPath = url.path
    }

    private static func mask(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "" }
        return "••••" + String(key.suffix(4))
    }
}
