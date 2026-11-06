import Foundation
import WebKit

/// Builds the web view for one account: its own private website storage, an iPhone Safari
/// identity, and the hiding rules installed before any page content loads.
enum WebViewFactory {
    static func make(storeID: UUID) -> WKWebView {
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
