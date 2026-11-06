import LocalAuthentication
import SafariServices
import SwiftUI

/// Covers the app until Face ID (or the phone's passcode as a fallback) succeeds.
struct LockScreen: View {
    let onUnlock: () -> Void
    @State private var message: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
            Text("Quiet is locked")
                .font(.headline)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Unlock") { Task { await unlock() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task { await unlock() }
    }

    private func unlock() async {
        let context = LAContext()
        do {
            // deviceOwnerAuthentication = Face ID, falling back to the phone's passcode.
            if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open your messages") {
                onUnlock()
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Safari's in-app viewer for links that leave Instagram. It runs outside this app's web
/// storage, so the page it shows cannot see any account's login.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
