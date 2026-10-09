// Fetches a Canvas calendar feed for the BamBoozled web app.
//
// Browsers won't let a web page read another site (Canvas) unless that site allows it, and Canvas
// doesn't, so the web app asks this function to fetch the feed instead. The phone and desktop apps
// fetch it themselves and don't use this.
//
// Only signed-in users of this project can call it (Supabase checks the user's token before the
// function runs), and it only fetches Canvas calendar feed links, so it can't be used to fetch
// anything else. The link is used for this one request and never stored or logged.
//
// Deploy:  supabase functions deploy canvas-feed
// Optional: limit it to your school's Canvas with a secret, e.g.
//          supabase secrets set CANVAS_HOSTS=canvas.nus.edu.sg

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const maxBytes = 5 * 1024 * 1024;

function configuredHosts(): string[] {
  // deno-lint-ignore no-explicit-any
  const env = (globalThis as any).Deno?.env?.get?.("CANVAS_HOSTS") ?? "";
  return env.split(",").map((h: string) => h.trim().toLowerCase()).filter(Boolean);
}

function fail(status: number, reason: string, upstream?: number): Response {
  return new Response(JSON.stringify({ reason, upstream }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** A Canvas calendar feed: https://<canvas host>/feeds/calendars/<private id>.ics */
export function isCanvasFeed(raw: unknown, allowedHosts = configuredHosts()): URL | null {
  if (typeof raw !== "string" || raw.length > 2000) return null;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.username || url.password || url.port) return null;
  if (!/^\/feeds\/calendars\/[A-Za-z0-9_.-]+\.ics$/.test(url.pathname)) return null;
  if (allowedHosts.length > 0 && !allowedHosts.includes(url.hostname.toLowerCase())) return null;
  return url;
}

export async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail(405, "method");
  if (!req.headers.get("authorization")) return fail(401, "signed_out");

  let body: { url?: unknown };
  try {
    body = await req.json();
  } catch {
    return fail(400, "not_a_feed");
  }
  const url = isCanvasFeed(body.url);
  if (!url) return fail(400, "not_a_feed");

  let upstream: Response;
  try {
    upstream = await fetch(url, { redirect: "follow", signal: AbortSignal.timeout(30_000) });
  } catch {
    return fail(502, "unreachable");
  }
  if ([401, 403, 404].includes(upstream.status)) return fail(502, "not_recognised", upstream.status);
  if (!upstream.ok) return fail(502, "unreachable", upstream.status);

  const text = await upstream.text();
  if (text.length > maxBytes || !text.includes("BEGIN:VCALENDAR")) return fail(502, "not_a_feed");
  return new Response(text, {
    headers: { ...corsHeaders, "Content-Type": "text/calendar; charset=utf-8", "Cache-Control": "no-store" },
  });
}

// deno-lint-ignore no-explicit-any
if ((import.meta as any).main) (globalThis as any).Deno.serve(handle);
