// Rules for "peek": reading a chat while the page's own "Seen" requests are held back.
// Pure logic, no page access, so it is tested outside the app (PageTests/peek.test.js).
// quiet.js connects it to the page.
//
// A peek has three states:
//   off     nothing is held back.
//   armed   a chat row was long-pressed; the chat is about to open. Seen is held already,
//           because the page may report it before the address has changed.
//   active  the chat is open. Stays active on that chat and on anything opened from it
//           (a photo, a reel, a story, a profile), and ends on arriving at any other
//           messages page: the inbox or a different chat.
//
// How the page reports "Seen" (live site, 2026-11-15): a GraphQL request named
// useIGDMarkThreadAsReadMutation, with a ...Validation twin. Stories and reels report
// through ...SeenMutation requests. Older REST addresses ended in /seen/.
(function (root) {
  const KEY = "quietPeek";
  const ARM_WINDOW_MS = 15000;
  const SEEN_NAME = /Seen|Mark\w*Read/;
  const SEEN_ADDRESS = /\/seen\/?(\?|$)/;
  // The two "mark chat as read" requests by number, in case one arrives without its name.
  const SEEN_DOC = /(^|&)doc_id=(27399783383056109|35211594988486314)(&|$)/;

  function threadOf(path) {
    const match = /^\/direct\/t\/([^/]+)/.exec(path || "");
    return match ? match[1] : null;
  }

  /// The name Instagram gives a request, from its body in whichever form it was sent.
  function requestName(body) {
    const field = "fb_api_req_friendly_name";
    if (typeof body === "string") {
      const match = new RegExp("(?:^|&)" + field + "=([^&]*)").exec(body);
      if (!match) return "";
      try {
        return decodeURIComponent(match[1]);
      } catch (error) {
        return match[1];
      }
    }
    if (body && typeof body.get === "function") {
      const value = body.get(field);
      return typeof value === "string" ? value : "";
    }
    return "";
  }

  function create(storage, now) {
    // Kept in memory as well, so a browser that refuses storage still peeks correctly
    // until the next full page load.
    let memory = { state: "off", at: 0, thread: null, held: 0 };

    function save(next) {
      memory = next;
      try {
        if (next.state === "off") storage.removeItem(KEY);
        else storage.setItem(KEY, JSON.stringify(next));
      } catch (error) {}
    }

    function load() {
      try {
        const stored = storage.getItem(KEY);
        if (stored) memory = JSON.parse(stored);
      } catch (error) {}
    }

    function current() {
      if (memory.state === "armed" && now() - memory.at > ARM_WINDOW_MS) {
        save({ state: "off", at: 0, thread: null, held: 0 });
      }
      return memory;
    }

    load();

    return {
      state() {
        return current().state;
      },

      /// A chat row was long-pressed.
      arm() {
        save({ state: "armed", at: now(), thread: null, held: 0 });
      },

      /// The page is now showing `path`. Returns the state that follows.
      visit(path) {
        const peek = current();
        const thread = threadOf(path);
        if (peek.state === "armed" && thread) {
          save({ state: "active", at: peek.at, thread, held: peek.held });
        } else if (peek.state === "active" && (path || "").startsWith("/direct/") && thread !== peek.thread) {
          save({ state: "off", at: 0, thread: null, held: 0 });
        }
        return memory.state;
      },

      /// The chat is being opened for real.
      end() {
        save({ state: "off", at: 0, thread: null, held: 0 });
      },

      /// Whether an outgoing request must be dropped. `url` is its address, `name`
      /// Instagram's name for it, `body` its text when it has one.
      holds(request) {
        const peek = current();
        if (peek.state === "off") return false;
        const url = request.url || "";
        const name = request.name || "";
        const body = typeof request.body === "string" ? request.body : "";
        const reportsSeen =
          SEEN_ADDRESS.test(url) ||
          (name.endsWith("Mutation") && SEEN_NAME.test(name)) ||
          SEEN_DOC.test(body);
        if (reportsSeen) save({ state: peek.state, at: peek.at, thread: peek.thread, held: peek.held + 1 });
        return reportsSeen;
      },

      /// How many requests this peek has held back so far.
      held() {
        return current().held;
      },
    };
  }

  root.QuietPeek = { create, requestName };
})(typeof window !== "undefined" ? window : globalThis);
