import Combine
import Foundation
import os
import QuietCore
import WebKit

/// One account's web view plus the rules that govern it. Every address the page tries to
/// show, by a full load or by an in-page move, goes through RouteGuard here.
@MainActor
final class AccountBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let account: Account
    let webView: WKWebView
    /// Why the page is not showing, when Instagram refused the request or could not be
    /// reached. Shown over the web view with a retry button instead of a blank page.
    @Published private(set) var loadProblem: String?
    #if DEBUG
    /// The last trace lines, shown on screen in diagnostic builds.
    @Published private(set) var traceLines: [String] = []
    #endif

    private static let origin = URL(string: "https://www.instagram.com")!
    private static let log = Logger(subsystem: "local.quiet.app", category: "browser")

    /// Diagnostic trace, debug builds only. Paths can name chats and people, so release
    /// builds write nothing to the device log.
    private func trace(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        let label = account.label
        Self.log.notice("[\(label, privacy: .public)] \(text, privacy: .public)")
        traceLines.append(text)
        if traceLines.count > 6 { traceLines.removeFirst(traceLines.count - 6) }
        #endif
    }

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

    func retry() {
        loadProblem = nil
        if webView.url != nil {
            webView.reload()
        } else {
            showInbox()
        }
    }

    private func loadFailed(_ error: Error) {
        let failure = error as NSError
        // Not failures: a load we cancelled ourselves, or one replaced by a newer load.
        if failure.code == NSURLErrorCancelled { return }
        if failure.domain == "WebKitErrorDomain", failure.code == 102 { return }
        loadProblem = error.localizedDescription
    }

    // MARK: - Deciding

    private func show(path: String) {
        guard let url = URL(string: path, relativeTo: Self.origin) else { return }
        webView.load(URLRequest(url: url))
    }

    private func addressChanged() {
        guard let url = webView.url, url != lastAllowed else { return }
        let decision = routeGuard.decide(url: url, from: lastAllowed)
        trace("address \(url.host() ?? "?")\(url.path()) -> \(decision)")
        switch decision {
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

        let decision = routeGuard.decide(url: url, from: webView.url)
        trace("load \(url.host() ?? "?")\(url.path()) -> \(decision)")
        switch decision {
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
        trace("commit \(webView.url?.path() ?? "?")")
        // A fresh page starts from quiet.js's strict defaults; give it the real state.
        sendStateToPage()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse {
            trace("response \(http.statusCode) \(http.url?.path() ?? "?") type=\(http.mimeType ?? "?") length=\(http.expectedContentLength)")
            switch http.statusCode {
            case 429:
                loadProblem = "Instagram is refusing requests from this connection for now (error 429). Wait a little, then try again."
            case 400...:
                loadProblem = "Instagram answered with error \(http.statusCode)."
            default:
                loadProblem = nil
            }
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        trace("start \(webView.url?.path() ?? "?")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        trace("finish \(webView.url?.path() ?? "?") frame=\(webView.frame.debugDescription) inWindow=\(webView.window != nil)")
        #if DEBUG
        webView.evaluateJavaScript(
            "JSON.stringify({ua: navigator.userAgent, ready: document.readyState, bodyLen: document.body ? document.body.innerHTML.length : -1, textLen: document.body ? document.body.innerText.length : -1, quiet: typeof window.__quiet, style: !!document.getElementById('quiet-style'), attrs: Object.assign({}, document.documentElement.dataset), w: innerWidth, h: innerHeight})"
        ) { [weak self] result, error in
            self?.trace("page \(result as? String ?? "nil") error=\(error?.localizedDescription ?? "none")")
        }
        #endif
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        trace("failProvisional \((error as NSError).domain) \((error as NSError).code) \(error.localizedDescription)")
        loadFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        trace("fail \((error as NSError).domain) \((error as NSError).code) \(error.localizedDescription)")
        loadFailed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        trace("web content process terminated")
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
