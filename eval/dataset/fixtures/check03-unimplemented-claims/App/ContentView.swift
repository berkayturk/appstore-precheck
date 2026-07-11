import SwiftUI

struct ContentView: View {
    @State private var tasks: [String] = []
    @State private var newTask = ""

    var body: some View {
        List {
            ForEach(tasks, id: \.self) { Text($0) }
            HStack {
                TextField("New task", text: $newTask)
                Button("Add") {
                    guard !newTask.isEmpty else { return }
                    tasks.append(newTask)
                    newTask = ""
                }
            }
        }
    }
}
