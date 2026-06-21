import Foundation
import Carbon.HIToolbox

public func carbonModifiers(command: Bool, control: Bool, option: Bool, shift: Bool) -> UInt32 {
    var mask: UInt32 = 0
    if command { mask |= UInt32(cmdKey) }
    if control { mask |= UInt32(controlKey) }
    if option  { mask |= UInt32(optionKey) }
    if shift   { mask |= UInt32(shiftKey) }
    return mask
}

public enum HotKeyConstants {
    public static let mKeyCode: UInt32 = UInt32(kVK_ANSI_M)  // 46
}
