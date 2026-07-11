import SwiftUI

struct SettingsView: View {
    @AppStorage("aiSortEnabled") private var aiSortEnabled = false

    var body: some View {
        Form {
            Section("Inbox") {
                Toggle(isOn: $aiSortEnabled) {
                    VStack(alignment: .leading) {
                        Text("AI Sort")
                        Text("Experimental: may be unstable and lose sort order")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
