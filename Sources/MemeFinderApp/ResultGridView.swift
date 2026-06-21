import SwiftUI
import MemeFinder

public struct ResultGridView: View {
    public let results: [SearchResult]
    public let onTap: (SearchResult) -> Void
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    public init(results: [SearchResult], onTap: @escaping (SearchResult) -> Void) {
        self.results = results; self.onTap = onTap
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(results) { r in
                    Button { onTap(r) } label: {
                        AsyncThumbnail(path: r.image.path)
                    }
                    .buttonStyle(.plain)
                    .help("點一下複製到剪貼簿")
                }
            }
            .padding()
        }
    }
}

struct AsyncThumbnail: View {
    let path: String
    var body: some View {
        Group {
            if let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
