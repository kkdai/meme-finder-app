import Testing
@testable import MemeFinder

@Test func carbonModifiersCombinesCommandAndControl() {
    // Carbon: cmdKey = 0x0100 (256), controlKey = 0x1000 (4096)
    #expect(carbonModifiers(command: true, control: true, option: false, shift: false) == 256 | 4096)
}

@Test func carbonModifiersEachFlagContributesIndependently() {
    #expect(carbonModifiers(command: true, control: false, option: false, shift: false) == 256)
    #expect(carbonModifiers(command: false, control: true, option: false, shift: false) == 4096)
    #expect(carbonModifiers(command: false, control: false, option: true, shift: false) == 2048)
    #expect(carbonModifiers(command: false, control: false, option: false, shift: true) == 512)
}

@Test func carbonModifiersEmptyIsZero() {
    #expect(carbonModifiers(command: false, control: false, option: false, shift: false) == 0)
}

@Test func mKeyCodeIs46() {
    #expect(HotKeyConstants.mKeyCode == 46)
}
