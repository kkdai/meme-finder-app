import SwiftUI
import MemeFinder

public struct ContentView: View {
    @ObservedObject var vm: SearchViewModel
    @State private var copiedID: String?
    public init(vm: SearchViewModel) { self.vm = vm }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜尋迷因…例如：謝謝、無言、好棒", text: $vm.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await vm.runSearch() } }
                Button("搜尋") { Task { await vm.runSearch() } }
            }
            .padding()

            if let msg = vm.errorMessage {
                Text(msg).foregroundStyle(.red).padding(.horizontal)
            }
            if let id = copiedID {
                Text("已複製 ✓").foregroundStyle(.green).padding(.horizontal).id(id)
            }

            ResultGridView(results: vm.results) { r in
                vm.copy(r)
                copiedID = r.id
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
