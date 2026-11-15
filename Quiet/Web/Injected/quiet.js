// Page-side half of the blocking. It does three things only:
//   1. puts the current state on <html> as data-quiet-* attributes, which quiet.css keys on;
//   2. stops videos from playing where video is not allowed;
//   3. peek: a long press on a chat in the inbox opens it while the page's "Seen" requests
//      are held back (rules in peek.js).
// It never reads form fields, and on login and security-check pages it removes its
// attributes and does nothing.
//
// Outgoing requests pass through this file untouched and unread. Only while a peek is on
// (which can only start from the inbox, never on a login page) is each request's address
// and name compared against the "Seen" patterns, here in the page; nothing is copied,
// stored or sent anywhere.
//
// The app calls window.__quiet.apply(...) at page start and on every address change,
// with the route decision already made by RouteGuard.
(() => {
  if (window.__quiet) return;

  const AUTH = /^\/(accounts\/(login|onetap)|challenge)(\/|$)/;
  const root = document.documentElement;
  let videoAllowed = true;

  function routeName(path) {
    if (path === "/") return "feed";
    if (path.startsWith("/explore")) return "explore";
    if (path.startsWith("/direct/")) return "direct";
    if (path.startsWith("/stories/")) return "stories";
    return "other";
  }

  function stop(video) {
    video.muted = true;
    video.autoplay = false;
    if (!video.paused) video.pause();
  }

  // "play" does not bubble, so listen in the capture phase to catch every video.
  document.addEventListener(
    "play",
    (event) => {
      if (!videoAllowed && event.target instanceof HTMLVideoElement) stop(event.target);
    },
    true
  );

  // ---- Peek -------------------------------------------------------------------------

  // The peek state lives in sessionStorage so it survives a full page load between the
  // inbox and the chat. Reached through functions because merely touching sessionStorage
  // can throw when storage is refused; peek.js then keeps the state in memory.
  const peek = window.QuietPeek.create(
    {
      getItem: (key) => window.sessionStorage.getItem(key),
      setItem: (key, value) => window.sessionStorage.setItem(key, value),
      removeItem: (key) => window.sessionStorage.removeItem(key),
    },
    Date.now
  );
  let reported = "";

  /// Shows the peek state on <html> for quiet.css and tells the app, which draws the banner.
  function reportPeek() {
    const message = { peek: peek.state(), held: peek.held() };
    if (AUTH.test(location.pathname)) delete root.dataset.quietPeek;
    else root.dataset.quietPeek = message.peek === "off" ? "off" : "on";
    const key = message.peek + ":" + message.held;
    if (key === reported) return;
    reported = key;
    try {
      window.webkit.messageHandlers.quietPeek.postMessage(message);
    } catch (error) {}
  }

  /// True when this outgoing request reports something as seen during a peek, in which
  /// case the caller drops it. Outside a peek it returns at the first line.
  function heldBack(url, body) {
    if (peek.state() === "off") return false;
    if (AUTH.test(location.pathname)) return false;
    peek.visit(location.pathname);
    const dropped = peek.holds({ url: String(url || ""), name: window.QuietPeek.requestName(body), body });
    reportPeek();
    return dropped;
  }

  const addresses = new WeakMap();
  const xhrOpen = XMLHttpRequest.prototype.open;
  const xhrSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    addresses.set(this, url);
    return xhrOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function (body) {
    // A held request is simply never sent. The page waits for an answer that does not
    // come, which is quieter than an error it might retry or show.
    if (heldBack(addresses.get(this), body)) return;
    return xhrSend.apply(this, arguments);
  };

  const pageFetch = window.fetch;
  window.fetch = function (input, init) {
    const url = typeof input === "string" ? input : (input && input.url) || "";
    if (heldBack(url, init && init.body)) return new Promise(() => {});
    return pageFetch.apply(this, arguments);
  };

  if (navigator.sendBeacon) {
    const pageBeacon = navigator.sendBeacon;
    navigator.sendBeacon = function (url, data) {
      if (heldBack(url, data)) return true;
      return pageBeacon.apply(this, arguments);
    };
  }

  // Long press on a chat row in the inbox.
  const HOLD_MS = 450;
  const MOVE_PX = 10;
  let press = null;
  let swallowClickUntil = 0;

  function onChatList() {
    const path = location.pathname;
    return path.startsWith("/direct/") && !path.startsWith("/direct/t/");
  }

  /// The inbox row under a touch: the nearest row-sized block that carries an avatar.
  /// Found by shape, because the rows have no address and Instagram's class names change.
  function chatRow(target) {
    for (let element = target; element && element !== document.body; element = element.parentElement) {
      if (!(element instanceof Element)) continue;
      if (element.matches('a[href^="/direct/t/"]')) return element;
      const box = element.getBoundingClientRect();
      if (box.height < 48 || box.width < 200) continue;
      if (box.height > 130) return null;
      const pictures = element.querySelectorAll("img").length;
      if (pictures >= 1 && pictures <= 3) return element;
    }
    return null;
  }

  function cancelPress() {
    if (press) clearTimeout(press.timer);
    press = null;
  }

  function firePress() {
    if (!press) return;
    press.fired = true;
    peek.arm();
    reportPeek();
    // Open the chat the way a tap would, now that Seen is being held.
    press.target.click();
  }

  document.addEventListener(
    "pointerdown",
    (event) => {
      cancelPress();
      if (!event.isPrimary || !onChatList() || !(event.target instanceof Element)) return;
      if (!chatRow(event.target)) return;
      press = { target: event.target, x: event.clientX, y: event.clientY, fired: false, timer: setTimeout(firePress, HOLD_MS) };
    },
    true
  );
  document.addEventListener(
    "pointermove",
    (event) => {
      if (!press || press.fired) return;
      if (Math.hypot(event.clientX - press.x, event.clientY - press.y) > MOVE_PX) cancelPress();
    },
    true
  );
  for (const type of ["pointerup", "pointercancel"]) {
    document.addEventListener(
      type,
      () => {
        // Lifting the finger after the chat has opened would count as a tap on whatever
        // is now underneath it. Swallow that one tap.
        if (press && press.fired && !onChatList()) swallowClickUntil = Date.now() + 700;
        cancelPress();
      },
      true
    );
  }
  document.addEventListener(
    "click",
    (event) => {
      if (!event.isTrusted || Date.now() > swallowClickUntil) return;
      swallowClickUntil = 0;
      event.preventDefault();
      event.stopImmediatePropagation();
    },
    true
  );
  // The system's own long-press menu would cover the row being pressed.
  document.addEventListener(
    "contextmenu",
    (event) => {
      if (onChatList() && event.target instanceof Element && chatRow(event.target)) event.preventDefault();
    },
    true
  );

  // ---- State from the app -----------------------------------------------------------

  window.__quiet = {
    apply({ path, feed, stories, video }) {
      if (AUTH.test(path)) {
        delete root.dataset.quietRoute;
        delete root.dataset.quietVideo;
        delete root.dataset.quietFeed;
        delete root.dataset.quietStories;
        delete root.dataset.quietList;
        videoAllowed = true;
        peek.end();
        reportPeek();
        return;
      }
      root.dataset.quietRoute = routeName(path);
      root.dataset.quietVideo = video ? "on" : "off";
      root.dataset.quietFeed = feed ? "on" : "off";
      root.dataset.quietStories = stories ? "on" : "off";
      root.dataset.quietList = path.startsWith("/direct/") && !path.startsWith("/direct/t/") ? "on" : "off";
      videoAllowed = video;
      if (!video) document.querySelectorAll("video").forEach(stop);
      peek.visit(path);
      reportPeek();
    },

    /// Ends a peek by hand (the banner's buttons). The app then reloads or leaves the chat.
    endPeek() {
      peek.end();
      reportPeek();
    },
  };

  // Until the app sends the real state (a few milliseconds after the page starts), assume
  // the strictest one, so nothing that should be hidden flashes into view.
  window.__quiet.apply({
    path: location.pathname,
    feed: false,
    stories: false,
    video: /^\/(direct|stories)\//.test(location.pathname),
  });
})();
