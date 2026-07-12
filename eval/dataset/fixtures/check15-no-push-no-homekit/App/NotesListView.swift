import SwiftUI

struct NotesListView: View {
    @State private var notes: [String] = ["Groceries", "Meeting agenda"]

    var body: some View {
        NavigationStack {
            List(notes, id: \.self) { note in
                Text(note)
            }
            .navigationTitle("Notes")
        }
    }
}
