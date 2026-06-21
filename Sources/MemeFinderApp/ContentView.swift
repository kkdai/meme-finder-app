import SwiftUI
import MemeFinder

public struct ContentView: View {
    @ObservedObject var vm: SearchViewModel
    @State private var copiedID: String?
    @State private var didSearch = false
    public init(vm: SearchViewModel) { self.vm = vm }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜尋迷因…例如：謝謝、無言、好棒", text: $vm.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await vm.runSearch(); didSearch = true } }
                Button("搜尋") { Task { await vm.runSearch(); didSearch = true } }
            }
            .padding()

            if let msg = vm.errorMessage {
                Text(msg).foregroundStyle(.red).padding(.horizontal)
            }
            if let id = copiedID {
                Text("已複製 ✓").foregroundStyle(.green).padding(.horizontal).id(id)
            }

            if didSearch && vm.results.isEmpty && vm.errorMessage == nil {
                Text("找不到相關迷因，換個關鍵字，或到設定重新索引").foregroundStyle(.secondary).padding()
            }
            ResultGridView(results: vm.results) { r in
                vm.copy(r)
                copiedID = r.id
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
