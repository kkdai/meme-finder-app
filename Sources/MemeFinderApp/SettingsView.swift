import SwiftUI
import AppKit
import MemeFinder

public struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var keyField: String = ""
    let onReindex: () -> Void
    public init(vm: SettingsViewModel, onReindex: @escaping () -> Void = {}) {
        self.vm = vm; self.onReindex = onReindex
    }

    public var body: some View {
        Form {
            Section("Gemini API 金鑰") {
                HStack {
                    SecureField("貼上 API 金鑰", text: $keyField)
                    Button("儲存") { vm.saveAPIKey(keyField); keyField = "" }
                }
                if !vm.maskedKey.isEmpty { Text("目前：\(vm.maskedKey)").foregroundStyle(.secondary) }
            }
            Section("迷因資料夾") {
                HStack {
                    Text(vm.folderPath ?? "尚未選擇").foregroundStyle(.secondary)
                    Spacer()
                    Button("選擇資料夾…") { chooseFolder() }
                }
                Button("重新索引") { onReindex() }
                    .disabled(vm.folderPath == nil || !vm.hasAPIKey)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { vm.setFolder(url) }
    }
}
