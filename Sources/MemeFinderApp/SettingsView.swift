import SwiftUI
import AppKit
import MemeFinder

public struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @ObservedObject var indexing: IndexingController
    @State private var keyField: String = ""
    let onReindex: () -> Void
    let onCancel: () -> Void
    public init(vm: SettingsViewModel, indexing: IndexingController, onReindex: @escaping () -> Void = {}, onCancel: @escaping () -> Void = {}) {
        self.vm = vm; self.indexing = indexing; self.onReindex = onReindex; self.onCancel = onCancel
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
                if indexing.progress > 0 && indexing.progress < 1 {
                    Button("取消") { onCancel() }
                    ProgressView(value: indexing.progress)
                }
                if !indexing.statusText.isEmpty {
                    Text(indexing.statusText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        // Height is required here: hosted in a plain NSWindow (not a SwiftUI
        // Settings scene), a Form with no height constraint collapses to ~0,
        // which makes the window open as a blank strip.
        .frame(width: 460, height: 320)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { vm.setFolder(url) }
    }
}
