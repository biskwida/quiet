import Foundation
import WebKit

#if DEBUG
/// Diagnostic builds only: receives the page's script errors and failed requests.
final class DebugMessageRelay: NSObject, WKScriptMessageHandler {
    var onMessage: ((String) -> Void)?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let text = message.body as? String { onMessage?(text) }
    }

    /// Reports what the page's own code runs into. Debug builds only; never in release.
    static let script = #"""
    (() => {
      const send = (t) => { try { window.webkit.messageHandlers.quietDebug.postMessage(String(t).slice(0, 220)); } catch (e) {} };
      const short = (u) => String(u || "").replace(/^https?:\/\/[^/]+/, "").split("?")[0].slice(0, 70);
      window.addEventListener("error", (e) => send("jserror " + e.message + " @" + short(e.filename) + ":" + e.lineno));
      window.addEventListener("unhandledrejection", (e) => send("rejection " + (e.reason && (e.reason.message || e.reason))));
      const fetch0 = window.fetch;
      window.fetch = function (input, init) {
        const u = typeof input === "string" ? input : (input && input.url) || "";
        return fetch0.apply(this, arguments).then((r) => { if (!r.ok) send("fetch " + r.status + " " + short(u)); return r; },
                                                  (err) => { send("fetch FAIL " + short(u) + " " + err.message); throw err; });
      };
      const open0 = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (m, u) {
        this.addEventListener("loadend", () => { if (this.status === 0 || this.status >= 400) send("xhr " + this.status + " " + short(u)); });
        return open0.apply(this, arguments);
      };
      try { localStorage.setItem("__quiet", "1"); localStorage.removeItem("__quiet"); } catch (e) { send("localStorage ERR " + e.message); }
      try { const r = indexedDB.open("__quiet"); r.onerror = () => send("indexedDB ERR " + (r.error && r.error.message)); } catch (e) { send("indexedDB ERR " + e.message); }
      send("debug hooks on");
    })();
    """#
}
#endif

/// Builds the web view for one account: its own private website storage, an iPhone Safari
/// identity, and the hiding rules installed before any page content loads.
enum WebViewFactory {
    static func make(storeID: UUID, debugRelay: AnyObject? = nil) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // One isolated store per account. Cookies and the login session never mix between
        // accounts, and removing the store signs that account out completely.
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        // Without this suffix the site sees an unknown browser instead of iPhone Safari.
        configuration.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"
        configuration.allowsInlineMediaPlayback = true
        for script in userScripts {
            configuration.userContentController.addUserScript(script)
        }
        #if DEBUG
        if let relay = debugRelay as? DebugMessageRelay {
            configuration.userContentController.add(relay, name: "quietDebug")
            configuration.userContentController.addUserScript(
                WKUserScript(source: DebugMessageRelay.script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }
        #endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }

    /// quiet.css and quiet.js from the app bundle, run at the very start of every page.
    private static let userScripts: [WKUserScript] = {
        let css = resource("quiet", "css")
        let js = resource("quiet", "js")
        // The stylesheet goes in through a script because that is the only way to add one
        // before the page's own content. JSON encoding makes the CSS a safe string literal.
        guard let literal = try? String(data: JSONEncoder().encode(css), encoding: .utf8) else {
            fatalError("quiet.css could not be encoded")
        }
        let addStyle = """
        (() => {
          const style = document.createElement("style");
          style.id = "quiet-style";
          style.textContent = \(literal);
          (document.head || document.documentElement).appendChild(style);
        })();
        """
        return [addStyle, js].map {
            WKUserScript(source: $0, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        }
    }()

    /// A build without the hiding rules would show everything this app exists to remove,
    /// so a missing file stops the app instead of running unprotected.
    private static func resource(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            fatalError("\(name).\(ext) is missing from the app bundle")
        }
        return text
    }
}
