import Testing
import Foundation
@testable import MemeFinder

private final class StubService: GeminiService, @unchecked Sendable {
    func annotate(imageData: Data, mimeType: String) async throws -> Annotation {
        Annotation(ocrText: "", description: "", tags: [], emotion: "")
    }
    func embed(text: String) async throws -> [Float] { [1, 0] }
}

private final class SpyClipboard: ClipboardWriter, @unchecked Sendable {
    var copied: [URL] = []
    func copyImage(at url: URL) throws { copied.append(url) }
}

@MainActor
@Test func runSearchPopulatesRankedResults() async {
    let index = MemeIndex(images: [
        IndexedImage(id: "/m/a.png", path: "/m/a.png", modifiedAt: Date(), ocrText: "", imageDescription: "",
                     tags: [], emotion: "", embedding: [1, 0]),
        IndexedImage(id: "/m/b.png", path: "/m/b.png", modifiedAt: Date(), ocrText: "", imageDescription: "",
                     tags: [], emotion: "", embedding: [0, 1]),
    ])
    let vm = SearchViewModel(service: StubService(), clipboard: SpyClipboard(), index: index)
    vm.query = "貓"
    await vm.runSearch()
    #expect(vm.results.map(\.image.id) == ["/m/a.png"])
}

@MainActor
@Test func blankQueryClearsResults() async {
    let vm = SearchViewModel(service: StubService(), clipboard: SpyClipboard(), index: MemeIndex())
    vm.query = "   "
    await vm.runSearch()
    #expect(vm.results.isEmpty)
}

@MainActor
@Test func showsAllImagesNewestFirstByDefault() {
    let older = IndexedImage(id: "/m/old.png", path: "/m/old.png", modifiedAt: Date(timeIntervalSince1970: 100),
                             ocrText: "", imageDescription: "", tags: [], emotion: "", embedding: [1])
    let newer = IndexedImage(id: "/m/new.png", path: "/m/new.png", modifiedAt: Date(timeIntervalSince1970: 200),
                             ocrText: "", imageDescription: "", tags: [], emotion: "", embedding: [1])
    let vm = SearchViewModel(service: StubService(), clipboard: SpyClipboard(), index: MemeIndex(images: [older, newer]))
    // Before any search, the grid shows every image, newest first.
    #expect(vm.results.map(\.image.id) == ["/m/new.png", "/m/old.png"])
}

@MainActor
@Test func blankQueryShowsAllImagesNewestFirst() async {
    let older = IndexedImage(id: "/m/old.png", path: "/m/old.png", modifiedAt: Date(timeIntervalSince1970: 100),
                             ocrText: "", imageDescription: "", tags: [], emotion: "", embedding: [1])
    let newer = IndexedImage(id: "/m/new.png", path: "/m/new.png", modifiedAt: Date(timeIntervalSince1970: 200),
                             ocrText: "", imageDescription: "", tags: [], emotion: "", embedding: [1])
    let vm = SearchViewModel(service: StubService(), clipboard: SpyClipboard(), index: MemeIndex(images: [older, newer]))
    vm.query = "   "
    await vm.runSearch()
    #expect(vm.results.map(\.image.id) == ["/m/new.png", "/m/old.png"])
}

@MainActor
@Test func updateIndexRefreshesBrowseNewestFirst() {
    let vm = SearchViewModel(service: StubService(), clipboard: SpyClipboard(), index: MemeIndex())
    #expect(vm.results.isEmpty)
    let a = IndexedImage(id: "/m/a.png", path: "/m/a.png", modifiedAt: Date(timeIntervalSince1970: 100),
                         ocrText: "", imageDescription: "", tags: [], emotion: "", embedding: [1])
    let b = IndexedImage(id: "/m/b.png", path: "/m/b.png", modifiedAt: Date(timeIntervalSince1970: 200),
                         ocrText: "", imageDescription: "", tags: [], emotion: "", embedding: [1])
    vm.updateIndex(MemeIndex(images: [a, b]))
    #expect(vm.results.map(\.image.id) == ["/m/b.png", "/m/a.png"])
}

@MainActor
@Test func copyDelegatesToClipboard() {
    let clip = SpyClipboard()
    let vm = SearchViewModel(service: StubService(), clipboard: clip, index: MemeIndex())
    let r = SearchResult(image: IndexedImage(id: "/m/a.png", path: "/m/a.png", modifiedAt: Date(),
        ocrText: "", imageDescription: "", tags: [], emotion: "", embedding: [1]), score: 1)
    vm.copy(r)
    #expect(clip.copied.map(\.path) == ["/m/a.png"])
}
