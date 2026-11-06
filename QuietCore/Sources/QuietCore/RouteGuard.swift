import Foundation

/// What the app should do with an address the page wants to show.
public enum Decision: Equatable, Sendable {
    /// Show it inside the app.
    case allow
    /// Refuse it and show this Instagram path instead (the inbox, or the chat a shared item came from).
    case sendTo(String)
    /// Not Instagram: hand it to Safari's in-app viewer, which cannot see the login session.
    case openOutside
}

public struct GuardSettings: Equatable, Sendable {
    public var feedEnabled: Bool
    public var storiesEnabled: Bool
    /// Username of the logged-in account, so its own stories stay reachable.
    public var ownUsername: String?

    public init(feedEnabled: Bool = false, storiesEnabled: Bool = false, ownUsername: String? = nil) {
        self.feedEnabled = feedEnabled
        self.storiesEnabled = storiesEnabled
        self.ownUsername = ownUsername
    }
}

public struct RouteGuard: Sendable {
    public static let inboxPath = "/direct/inbox/"

    public var settings: GuardSettings
    private var shared: OpenSharedItem?

    public init(settings: GuardSettings = GuardSettings()) {
        self.settings = settings
    }

    /// Decides one navigation. `previous` is the address the page is leaving.
    ///
    /// A reel or story opened from a chat thread is remembered as the one shared item.
    /// While it is open, moving to any other reel, story or blocked section returns to that chat.
    public mutating func decide(url: URL, from previous: URL? = nil) -> Decision {
        guard Self.isInstagram(url) else { return .openOutside }
        let parts = Self.pathParts(url)
        let item = SharedItem(parts)

        if let open = shared {
            if item == open.item { return .allow }
            if item != nil || !isAllowed(parts) { return .sendTo(open.threadPath) }
            shared = nil
            return .allow
        }

        if let item, let previous, let threadPath = Self.threadPath(previous) {
            shared = OpenSharedItem(item: item, threadPath: threadPath)
            return .allow
        }

        return isAllowed(parts) ? .allow : .sendTo(Self.inboxPath)
    }

    /// Whether video may play on this page: in chats, in the story viewer, and on the one
    /// item opened from a chat. Everywhere else the page-side script stops it.
    public func allowsVideo(at url: URL) -> Bool {
        guard Self.isInstagram(url) else { return false }
        let parts = Self.pathParts(url)
        if parts.first == "direct" || parts.first == "stories" { return true }
        guard let open = shared else { return false }
        return SharedItem(parts) == open.item
    }

    /// Login, two-factor and security-check pages. The hiding scripts stay off on these.
    public static func isAuthPage(_ url: URL) -> Bool {
        guard isInstagram(url) else { return false }
        let parts = pathParts(url)
        guard let first = parts.first else { return false }
        if first == "challenge" { return true }
        return first == "accounts" && parts.count >= 2 && ["login", "onetap"].contains(parts[1])
    }

    private func isAllowed(_ parts: [String]) -> Bool {
        guard let first = parts.first else { return settings.feedEnabled }
        switch first {
        case "direct":
            return true
        case "reel", "reels":
            return false
        case "explore":
            // "/explore/" is where the site's Search button leads; its grid is hidden by CSS.
            // Tag, location and keyword listings underneath are grids of posts and stay closed.
            return parts.count == 1 || (parts.count == 2 && parts[1] == "search")
        case "stories":
            return settings.storiesEnabled || isOwnUsername(parts.count >= 2 ? parts[1] : nil)
        default:
            // "/<username>/reels/" is a profile's Reels tab, "/<username>/reel/<code>/" one of its reels.
            return !(parts.count >= 2 && (parts[1] == "reels" || parts[1] == "reel"))
        }
    }

    private func isOwnUsername(_ name: String?) -> Bool {
        guard let name, let own = settings.ownUsername else { return false }
        return name.lowercased() == own.lowercased()
    }

    private static func isInstagram(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
    }

    private static func pathParts(_ url: URL) -> [String] {
        url.path().split(separator: "/").map(String.init)
    }

    /// "/direct/t/<id>/" if the address is a chat thread.
    private static func threadPath(_ url: URL) -> String? {
        guard isInstagram(url) else { return nil }
        let parts = pathParts(url)
        guard parts.count >= 3, parts[0] == "direct", parts[1] == "t" else { return nil }
        return "/direct/t/\(parts[2])/"
    }
}

/// A single post, reel or story, identified independently of which address form shows it.
/// Instagram shows the same reel under "/reel/<code>/", "/reels/<code>/", "/p/<code>/" and
/// the "/<user>/..." variants of those, so posts and reels share one case keyed by the code.
private enum SharedItem: Equatable, Sendable {
    case media(code: String)
    case story(user: String, id: String)

    init?(_ parts: [String]) {
        guard let first = parts.first else { return nil }
        let mediaSections: Set<String> = ["p", "reel", "reels"]
        if mediaSections.contains(first), parts.count == 2 {
            self = .media(code: parts[1])
        } else if parts.count == 3, parts[1] == "p" || parts[1] == "reel" {
            self = .media(code: parts[2])
        } else if first == "stories", parts.count == 3, parts[1] != "highlights" {
            self = .story(user: parts[1].lowercased(), id: parts[2])
        } else {
            return nil
        }
    }
}

private struct OpenSharedItem: Sendable {
    let item: SharedItem
    let threadPath: String
}
