import Foundation

/// What the page says about "peek": reading a chat while its "Seen" requests are held back.
/// The page decides and enforces this (peek.js); the app only shows it.
public enum PeekStatus: Equatable, Sendable {
    case off
    /// A chat is being peeked. `held` is how many "Seen" requests were stopped so far.
    case peeking(held: Int)

    /// Reads the message quiet.js posts: `{peek: "off" | "armed" | "active", held: n}`.
    /// Anything unrecognised reads as off, so the banner never claims a peek that the page
    /// did not report.
    public init(pageMessage: Any) {
        guard let message = pageMessage as? [String: Any],
              let state = message["peek"] as? String,
              state == "armed" || state == "active"
        else {
            self = .off
            return
        }
        self = .peeking(held: message["held"] as? Int ?? 0)
    }

    public var isPeeking: Bool {
        self != .off
    }

    /// True once at least one "Seen" request was actually stopped, which is the evidence
    /// that the page tried to report the chat as read and could not.
    public var seenWasHeld: Bool {
        if case .peeking(let held) = self { return held > 0 }
        return false
    }
}
