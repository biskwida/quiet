import Foundation
import QuietCore
import WebKit

/// One account's web view plus the rules that govern it. Every address the page tries to
/// show, by a full load or by an in-page move, goes through RouteGuard here.
@MainActor
final class AccountBrowser: NSObject, WKNavigationDelegate, WKUIDelegate {
    let account: Account
    let webView: WKWebView

    private static let origin = URL(string: "https://www.instagram.com")!

    private var routeGuard: RouteGuard
    /// The last address RouteGuard allowed. It is what a new address is "coming from".
    private var lastAllowed: URL?
    private var observation: NSKeyValueObservation?
    private let openOutside: (URL) -> Void

    init(account: Account, settings: GuardSettings, openOutside: @escaping (URL) -> Void) {
        self.account = account
        self.routeGuard = RouteGuard(settings: settings)
        self.openOutside = openOutside
        self.webView = WebViewFactory.make(storeID: account.id)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        // `url` changes for in-page moves (pushState) as well as full loads, so this sees
        // the addresses the navigation delegate never gets asked about.
        observation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.addressChanged() }
        }
        show(path: RouteGuard.inboxPath)
    }

    /// Called when a switch changes. Re-checks the page that is showing right now, so
    /// turning the feed off while looking at it leaves it straight away.
    func update(settings: GuardSettings) {
        routeGuard.settings = settings
        guard let url = webView.url else { return }
        if case .sendTo(let path) = routeGuard.decide(url: url, from: lastAllowed) {
            show(path: path)
        } else {
            sendStateToPage()
        }
    }

    func showInbox() {
        show(path: RouteGuard.inboxPath)
    }

    // MARK: - Deciding

    private func show(path: String) {
        guard let url = URL(string: path, relativeTo: Self.origin) else { return }
        webView.load(URLRequest(url: url))
    }

    private func addressChanged() {
        guard let url = webView.url, url != lastAllowed else { return }
        switch routeGuard.decide(url: url, from: lastAllowed) {
        case .allow:
            lastAllowed = url
            sendStateToPage()
        case .sendTo(let path):
            show(path: path)
        case .openOutside:
            // An in-page move cannot leave Instagram; a full load that does is stopped in
            // decidePolicyFor before it gets here.
            break
        }
    }

    /// Tells quiet.js what applies to the page now showing. The page decides nothing itself.
    private func sendStateToPage() {
        guard let url = webView.url else { return }
        let state: [String: Any] = [
            "path": url.path(),
            "feed": routeGuard.settings.feedEnabled,
            "stories": routeGuard.settings.storiesEnabled,
            "video": routeGuard.allowsVideo(at: url),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let json = String(data: data, encoding: .utf8)
        else { return }
        webView.evaluateJavaScript("window.__quiet && window.__quiet.apply(\(json)); null")
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        // Frames inside the page (embeds, login helpers) are not page changes.
        if let frame = navigationAction.targetFrame, !frame.isMainFrame { return .allow }
        guard let url = navigationAction.request.url else { return .cancel }
        // Anything that is not a web address (app links, phone numbers) is dropped, which
        // also keeps taps from jumping into the real Instagram app.
        guard url.scheme == "https" || url.scheme == "http" else { return .cancel }

        switch routeGuard.decide(url: url, from: webView.url) {
        case .allow:
            return .allow
        case .sendTo(let path):
            show(path: path)
            return .cancel
        case .openOutside:
            openOutside(url)
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // A fresh page starts from quiet.js's strict defaults; give it the real state.
        sendStateToPage()
    }

    // MARK: - WKUIDelegate

    /// Links that ask for a new window. decidePolicyFor has already let this one through,
    /// so it is an allowed Instagram address: show it in this view instead of nowhere.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    /// Camera and microphone for voice messages and posting, for Instagram's pages only.
    /// iOS still shows its own permission prompt the first time.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let host = origin.host.lowercased()
        let isInstagram = host == "instagram.com" || host.hasSuffix(".instagram.com")
        decisionHandler(isInstagram ? .grant : .deny)
    }
}
