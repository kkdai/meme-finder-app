import Testing
@testable import MemeFinder

@Test func inMemoryStoreRoundTrips() {
    let s = InMemorySecretStore()
    #expect(s.apiKey() == nil)
    s.setAPIKey("ABC")
    #expect(s.apiKey() == "ABC")
}
