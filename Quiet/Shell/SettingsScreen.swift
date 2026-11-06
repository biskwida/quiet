import QuietCore
import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var model: AppModel
    let onAddAccount: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var accountToRemove: Account?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Feed", isOn: $model.feedEnabled)
                    Toggle("Stories", isOn: $model.storiesEnabled)
                } header: {
                    Text("Show")
                } footer: {
                    Text("The feed shows pictures only. Reels stay off either way; a reel or story someone sends you in a chat always opens, on its own.")
                }

                Section("Accounts") {
                    ForEach(model.accounts.accounts) { account in
                        HStack {
                            Text(account.label)
                            Spacer()
                            Button("Remove", role: .destructive) { accountToRemove = account }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Add account", systemImage: "plus", action: onAddAccount)
                }

                Section {
                    Toggle("Require Face ID to open", isOn: $model.lockEnabled)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Your password is only ever typed on Instagram's own page. This app does not read or store it.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Remove \(accountToRemove?.label ?? "")?",
                isPresented: removeBinding,
                titleVisibility: .visible
            ) {
                Button("Remove and sign out", role: .destructive) {
                    if let account = accountToRemove { model.remove(account.id) }
                    accountToRemove = nil
                }
                Button("Cancel", role: .cancel) { accountToRemove = nil }
            } message: {
                Text("This erases the account's saved login from this phone. Your Instagram account itself is not affected.")
            }
        }
    }

    private var removeBinding: Binding<Bool> {
        Binding(get: { accountToRemove != nil }, set: { if !$0 { accountToRemove = nil } })
    }
}
