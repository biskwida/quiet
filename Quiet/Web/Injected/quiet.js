// Page-side half of the blocking. It does two things only:
//   1. puts the current state on <html> as data-quiet-* attributes, which quiet.css keys on;
//   2. stops videos from playing where video is not allowed.
// It never reads form fields, and on login and security-check pages it removes its
// attributes and does nothing.
//
// The app calls window.__quiet.apply(...) at page start and on every address change,
// with the decision already made by RouteGuard. This file decides nothing itself.
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

  window.__quiet = {
    apply({ path, feed, stories, video }) {
      if (AUTH.test(path)) {
        delete root.dataset.quietRoute;
        delete root.dataset.quietVideo;
        delete root.dataset.quietFeed;
        delete root.dataset.quietStories;
        videoAllowed = true;
        return;
      }
      root.dataset.quietRoute = routeName(path);
      root.dataset.quietVideo = video ? "on" : "off";
      root.dataset.quietFeed = feed ? "on" : "off";
      root.dataset.quietStories = stories ? "on" : "off";
      videoAllowed = video;
      if (!video) document.querySelectorAll("video").forEach(stop);
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
