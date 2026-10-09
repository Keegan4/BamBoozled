// Run with: node --experimental-strip-types --test supabase/functions/canvas-feed/index.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { handle, isCanvasFeed } from "./index.ts";

const feed = "https://canvas.nus.edu.sg/feeds/calendars/user_abc123.ics";
const ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n";

function post(body: unknown, auth = true): Request {
  return new Request("https://x.supabase.co/functions/v1/canvas-feed", {
    method: "POST",
    headers: { "content-type": "application/json", ...(auth ? { authorization: "Bearer t" } : {}) },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function withFetch(reply: (url: string) => Response | Promise<Response>) {
  const seen: string[] = [];
  globalThis.fetch = (async (input: string | URL) => {
    seen.push(String(input));
    return reply(String(input));
  }) as typeof fetch;
  return seen;
}

test("only Canvas calendar feed links are accepted", () => {
  assert.ok(isCanvasFeed(feed));
  for (const bad of [
    "http://canvas.nus.edu.sg/feeds/calendars/user_abc.ics",
    "https://canvas.nus.edu.sg/courses/1",
    "https://canvas.nus.edu.sg/feeds/calendars/../../secret.ics",
    "https://user:pw@canvas.example/feeds/calendars/a.ics",
    "https://canvas.example:8443/feeds/calendars/a.ics",
    "https://169.254.169.254/latest/meta-data",
    "not a url",
    42,
    "https://canvas.example/feeds/calendars/" + "a".repeat(3000) + ".ics",
  ]) {
    assert.equal(isCanvasFeed(bad), null, String(bad).slice(0, 80));
  }
});

test("CANVAS_HOSTS limits it to your school's Canvas", () => {
  assert.ok(isCanvasFeed(feed, ["canvas.nus.edu.sg"]));
  assert.equal(isCanvasFeed("https://other.instructure.com/feeds/calendars/a.ics", ["canvas.nus.edu.sg"]), null);
});

test("returns the calendar for a signed-in request", async () => {
  const seen = withFetch(() => new Response(ics));
  const res = await handle(post({ url: feed }));
  assert.equal(res.status, 200);
  assert.equal(await res.text(), ics);
  assert.match(res.headers.get("content-type")!, /text\/calendar/);
  assert.equal(res.headers.get("access-control-allow-origin"), "*");
  assert.deepEqual(seen, [feed]);
});

test("answers the browser's CORS check", async () => {
  const res = await handle(new Request("https://x/f", { method: "OPTIONS" }));
  assert.equal(res.status, 200);
  assert.match(res.headers.get("access-control-allow-headers")!, /authorization/);
});

test("refuses signed-out requests and other links without fetching anything", async () => {
  const seen = withFetch(() => new Response(ics));
  assert.equal((await handle(post({ url: feed }, false))).status, 401);
  const bad = await handle(post({ url: "https://evil.example/x" }));
  assert.equal(bad.status, 400);
  assert.equal((await bad.json()).reason, "not_a_feed");
  assert.equal((await handle(post("{not json"))).status, 400);
  assert.equal((await handle(new Request("https://x/f", { method: "GET" }))).status, 405);
  assert.deepEqual(seen, []);
});

test("explains Canvas refusing the link", async () => {
  for (const status of [401, 403, 404]) {
    withFetch(() => new Response("no", { status }));
    const res = await handle(post({ url: feed }));
    assert.equal(res.status, 502);
    assert.deepEqual(await res.json(), { reason: "not_recognised", upstream: status });
  }
});

test("reports Canvas being down or unreachable", async () => {
  withFetch(() => new Response("oops", { status: 500 }));
  assert.equal((await (await handle(post({ url: feed }))).json()).reason, "unreachable");
  withFetch(() => {
    throw new TypeError("network");
  });
  assert.equal((await (await handle(post({ url: feed }))).json()).reason, "unreachable");
});

test("refuses a reply that isn't a calendar (e.g. a login page)", async () => {
  withFetch(() => new Response("<html>Log in</html>"));
  const res = await handle(post({ url: feed }));
  assert.equal(res.status, 502);
  assert.equal((await res.json()).reason, "not_a_feed");
});
