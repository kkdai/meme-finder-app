import Testing
import Foundation
@testable import MemeFinder

@MainActor
@Test func savingKeyMasksAndPersists() {
    let secrets = InMemorySecretStore()
    let vm = SettingsViewModel(secrets: secrets,
                               bookmark: FolderBookmark(defaults: UserDefaults(suiteName: "t.\(UUID())")!, key: "k"))
    vm.saveAPIKey("  SECRET1234  ")
    #expect(secrets.apiKey() == "SECRET1234")
    #expect(vm.maskedKey == "••••1234")
    #expect(vm.hasAPIKey)
}

@MainActor
@Test func loadsExistingKeyOnInit() {
    let secrets = InMemorySecretStore()
    secrets.setAPIKey("ABCD9999")
    let vm = SettingsViewModel(secrets: secrets,
                               bookmark: FolderBookmark(defaults: UserDefaults(suiteName: "t.\(UUID())")!, key: "k"))
    #expect(vm.maskedKey == "••••9999")
}
