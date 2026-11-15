// Tests for Quiet/Web/Injected/peek.js, the rules behind "peek": reading a chat while the
// page's "Seen" requests are held back. Run with: node --test PageTests/
const test = require("node:test");
const assert = require("node:assert/strict");

require("../Quiet/Web/Injected/peek.js");
const { create, requestName } = globalThis.QuietPeek;

const THREAD = "/direct/t/111/";
const INBOX = "/direct/inbox/";
const MARK_READ = { url: "/api/graphql", name: "useIGDMarkThreadAsReadMutation", body: "" };

function setup() {
  const clock = { now: 1000 };
  const items = new Map();
  const storage = {
    getItem: (key) => (items.has(key) ? items.get(key) : null),
    setItem: (key, value) => items.set(key, String(value)),
    removeItem: (key) => items.delete(key),
  };
  return { clock, storage, peek: create(storage, () => clock.now) };
}

test("starts off and holds nothing back", () => {
  const { peek } = setup();
  assert.equal(peek.state(), "off");
  assert.equal(peek.holds(MARK_READ), false);
});

test("a long press arms it, and Seen is held from that moment", () => {
  const { peek } = setup();
  peek.arm();
  assert.equal(peek.state(), "armed");
  assert.equal(peek.holds(MARK_READ), true);
});

test("the first chat opened after arming becomes the peeked chat", () => {
  const { peek } = setup();
  peek.arm();
  assert.equal(peek.visit(THREAD), "active");
  assert.equal(peek.holds(MARK_READ), true);
});

test("still armed while the page is on the inbox, before the chat opens", () => {
  const { peek } = setup();
  peek.arm();
  assert.equal(peek.visit(INBOX), "armed");
});

test("arming lapses if no chat opens within 15 seconds", () => {
  const { peek, clock } = setup();
  peek.arm();
  clock.now += 15001;
  assert.equal(peek.state(), "off");
  assert.equal(peek.holds(MARK_READ), false);
  assert.equal(peek.visit(THREAD), "off");
});

test("an open peek does not lapse with time", () => {
  const { peek, clock } = setup();
  peek.arm();
  peek.visit(THREAD);
  clock.now += 3600000;
  assert.equal(peek.state(), "active");
  assert.equal(peek.holds(MARK_READ), true);
});

test("going back to the inbox ends the peek", () => {
  const { peek } = setup();
  peek.arm();
  peek.visit(THREAD);
  assert.equal(peek.visit(INBOX), "off");
  assert.equal(peek.holds(MARK_READ), false);
});

test("opening a different chat ends the peek", () => {
  const { peek } = setup();
  peek.arm();
  peek.visit(THREAD);
  assert.equal(peek.visit("/direct/t/222/"), "off");
});

test("a photo, reel or story opened from the peeked chat keeps the peek", () => {
  for (const item of ["/p/Abc/", "/reel/Abc/", "/stories/someone/123/", "/someone/"]) {
    const { peek } = setup();
    peek.arm();
    peek.visit(THREAD);
    assert.equal(peek.visit(item), "active", item);
    assert.equal(peek.visit(THREAD), "active", "back from " + item);
  }
});

test("the peek survives a full page reload", () => {
  const { peek, storage, clock } = setup();
  peek.arm();
  peek.visit(THREAD);
  const reloaded = create(storage, () => clock.now);
  assert.equal(reloaded.state(), "active");
  assert.equal(reloaded.visit(THREAD), "active");
  assert.equal(reloaded.visit(INBOX), "off");
});

test("ending it by hand turns it off, and it stays off after a reload", () => {
  const { peek, storage, clock } = setup();
  peek.arm();
  peek.visit(THREAD);
  peek.end();
  assert.equal(peek.state(), "off");
  assert.equal(create(storage, () => clock.now).state(), "off");
});

test("works in memory when the browser refuses storage", () => {
  const refuse = () => {
    throw new Error("storage is off");
  };
  const peek = create({ getItem: refuse, setItem: refuse, removeItem: refuse }, () => 0);
  peek.arm();
  assert.equal(peek.visit(THREAD), "active");
  assert.equal(peek.holds(MARK_READ), true);
});

test("holds every request that reports something as seen or read", () => {
  const { peek } = setup();
  peek.arm();
  const held = [
    { url: "/api/graphql", name: "useIGDMarkThreadAsReadMutation" },
    { url: "/api/graphql", name: "useIGDMarkThreadAsReadValidationMutation" },
    { url: "/api/graphql", name: "PolarisAPIReelSeenMutation" },
    { url: "/api/graphql", name: "", body: "av=1&doc_id=27399783383056109&variables=%7B%7D" },
    { url: "/api/graphql", name: "", body: "doc_id=35211594988486314" },
    { url: "/api/v1/direct_v2/threads/1/items/2/seen/" },
    { url: "https://www.instagram.com/api/v1/media/seen/?reel=1" },
  ];
  for (const request of held) assert.equal(peek.holds(request), true, JSON.stringify(request));
});

test("lets everything else through during a peek", () => {
  const { peek } = setup();
  peek.arm();
  const passed = [
    { url: "/api/graphql", name: "IGDirectTextSendMutation" },
    { url: "/api/graphql", name: "IGDInboxHeaderOffMsysQuery" },
    { url: "/api/graphql", name: "IGDThreadSeenStatusQuery" },
    { url: "/api/graphql", name: "", body: "doc_id=999&variables=%7B%7D" },
    { url: "/api/v1/news/inbox_seen/" },
    { url: "/ajax/bz" },
    {},
  ];
  for (const request of passed) assert.equal(peek.holds(request), false, JSON.stringify(request));
});

test("counts what it held, per peek", () => {
  const { peek } = setup();
  assert.equal(peek.held(), 0);
  peek.arm();
  peek.visit(THREAD);
  peek.holds(MARK_READ);
  peek.holds({ url: "/ajax/bz" });
  peek.holds(MARK_READ);
  assert.equal(peek.held(), 2);
  peek.visit(INBOX);
  peek.arm();
  assert.equal(peek.held(), 0);
});

test("the count survives a full page reload", () => {
  const { peek, storage, clock } = setup();
  peek.arm();
  peek.visit(THREAD);
  peek.holds(MARK_READ);
  assert.equal(create(storage, () => clock.now).held(), 1);
});

test("finds the request's name in each form a body can take", () => {
  const text = "av=1&fb_api_req_friendly_name=useIGDMarkThreadAsReadMutation&doc_id=1";
  assert.equal(requestName(text), "useIGDMarkThreadAsReadMutation");
  assert.equal(requestName(new URLSearchParams(text)), "useIGDMarkThreadAsReadMutation");
  const form = new FormData();
  form.set("fb_api_req_friendly_name", "PolarisAPIReelSeenMutation");
  assert.equal(requestName(form), "PolarisAPIReelSeenMutation");
  assert.equal(requestName("a=1&b=2"), "");
  assert.equal(requestName(null), "");
  assert.equal(requestName(new Uint8Array(4)), "");
});
