import SwiftUI

@main
struct PrecheckApp: App {
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}

struct HomeView: View {
    @State private var accountExists = true
    @State private var restored = false
    @State private var moderationStatus = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if accountExists {
                        Button("Delete Account") { accountExists = false }
                            .accessibilityIdentifier("account.delete")
                    } else {
                        Text("Account deleted")
                    }
                }
                Section("Purchases") {
                    Button("Restore Purchases") { restored = true }
                        .accessibilityIdentifier("purchase.restore")
                    if restored { Text("Restore request completed") }
                }
                Section("Community") {
                    Button("Report Content") { moderationStatus = "Report submitted" }
                        .accessibilityIdentifier("ugc.report")
                    Button("Block Member") { moderationStatus = "Member blocked" }
                        .accessibilityIdentifier("ugc.block")
                    if !moderationStatus.isEmpty { Text(moderationStatus) }
                }
            }
            .navigationTitle("Precheck Clean")
        }
    }
}
