import QuietCore
import SwiftUI
import WebKit

/// The whole app: a slim bar on top (accounts, settings) and the selected account's
/// Instagram below it. Visual design is deliberately plain here; it gets its own pass.
struct RootScreen: View {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSettings = false
    @State private var showAddAccount = false
    @State private var unlocked = false

    var body: some View {
        ZStack {
            if let browser = model.selectedBrowser {
                VStack(spacing: 0) {
                    TopBar(
                        model: model,
                        onInbox: { browser.showInbox() },
                        onAddAccount: { showAddAccount = true },
                        onSettings: { showSettings = true }
                    )
                    BrowserArea(browser: browser)
                }
            } else {
                WelcomeScreen { showAddAccount = true }
            }

            if model.lockEnabled && !unlocked {
                LockScreen { unlocked = true }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsScreen(model: model, onAddAccount: {
                showSettings = false
                showAddAccount = true
            })
        }
        .sheet(item: $model.externalPage) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
        .addAccountPrompt(isPresented: $showAddAccount) { model.addAccount(username: $0) }
        .alert("Something went wrong", isPresented: problemBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.problem ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            // Lock again whenever the app leaves the screen.
            if phase == .background { unlocked = false }
        }
    }

    private var problemBinding: Binding<Bool> {
        Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })
    }
}

private struct TopBar: View {
    @ObservedObject var model: AppModel
    let onInbox: () -> Void
    let onAddAccount: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack {
            Menu {
                ForEach(model.accounts.accounts) { account in
                    Button {
                        model.select(account.id)
                    } label: {
                        if account.id == model.accounts.selectedID {
                            Label(account.label, systemImage: "checkmark")
                        } else {
                            Text(account.label)
                        }
                    }
                }
                Divider()
                Button("Add account", systemImage: "plus", action: onAddAccount)
            } label: {
                HStack(spacing: 4) {
                    Text(model.accounts.selected?.label ?? "")
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.primary)
            }

            Spacer()

            Button("Messages", systemImage: "paperplane", action: onInbox)
                .labelStyle(.iconOnly)
            Button("Settings", systemImage: "gearshape", action: onSettings)
                .labelStyle(.iconOnly)
                .padding(.leading, 12)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.bar)
    }
}

/// The account's Instagram, or an explanation with a retry when it did not load.
private struct BrowserArea: View {
    @ObservedObject var browser: AccountBrowser

    var body: some View {
        ZStack {
            WebViewHost(webView: browser.webView)
                .ignoresSafeArea(.container, edges: .bottom)

            if let problem = browser.loadProblem {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Instagram didn't load")
                        .font(.headline)
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") { browser.retry() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
        }
    }
}

private struct WelcomeScreen: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Quiet")
                .font(.largeTitle.bold())
            Text("Instagram messages, without Reels.")
                .foregroundStyle(.secondary)
            Button("Add your Instagram account", action: onAdd)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding()
    }
}

/// Shows an account's web view. The web view outlives this SwiftUI view (each account keeps
/// its own, so switching back does not reload), so it is placed inside a plain container
/// rather than handed to SwiftUI to own.
private struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        attach(to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if webView.superview !== container { attach(to: container) }
    }

    private func attach(to container: UIView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
    }
}

extension View {
    /// Asks for the username only. The password is typed on Instagram's own page afterwards.
    func addAccountPrompt(isPresented: Binding<Bool>, onAdd: @escaping (String) -> Void) -> some View {
        modifier(AddAccountPrompt(isPresented: isPresented, onAdd: onAdd))
    }
}

private struct AddAccountPrompt: ViewModifier {
    @Binding var isPresented: Bool
    let onAdd: (String) -> Void
    @State private var username = ""

    func body(content: Content) -> some View {
        content.alert("Add account", isPresented: $isPresented) {
            TextField("Instagram username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add") {
                onAdd(username)
                username = ""
            }
            Button("Cancel", role: .cancel) { username = "" }
        } message: {
            Text("Only the username, to label the account. You sign in on Instagram's own page next.")
        }
    }
}
