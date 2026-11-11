// Hiello photo notifications: Supabase Edge Function "hiello-push".
// Supabase > Edge Functions > Deploy a new function > Via Editor > name it hiello-push > paste this file.
// Called only by the database (backend/push.sql) with a private secret; it then sends Apple notifications.
//
// Needs these Edge Function secrets (Supabase > Edge Functions > Secrets):
//   APNS_KEY     the whole text of your AuthKey_XXXXXXXXXX.p8 file, including the BEGIN/END lines
//   APNS_KEY_ID  the 10-character Key ID
//   APNS_TEAM_ID your 10-character Apple Team ID
// Optional: APNS_BUNDLE (default com.hiello.family), APNS_HOST (default api.push.apple.com)

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BUNDLE = Deno.env.get("APNS_BUNDLE") || "com.hiello.family";
const HOST = Deno.env.get("APNS_HOST") || "api.push.apple.com";

const db = (path: string, init: RequestInit = {}) =>
  fetch(`${SB_URL}${path}`, {
    ...init,
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json", ...(init.headers || {}) },
  });

async function one(table: string, query: string) {
  const r = await db(`/rest/v1/${table}?${query}&limit=1`);
  if (!r.ok) return null;
  const rows = await r.json();
  return rows[0] || null;
}
async function many(table: string, query: string) {
  const r = await db(`/rest/v1/${table}?${query}`);
  return r.ok ? await r.json() : [];
}

// ---------- Apple's sign-in token (ES256), made once and reused for 50 minutes ----------
let jwt = "", jwtAt = 0;
const b64url = (b: Uint8Array | string) =>
  btoa(typeof b === "string" ? b : String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
async function appleToken() {
  if (jwt && Date.now() - jwtAt < 50 * 60 * 1000) return jwt;
  const pem = (Deno.env.get("APNS_KEY") || "").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const head = b64url(JSON.stringify({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID") }));
  const body = b64url(JSON.stringify({ iss: Deno.env.get("APNS_TEAM_ID"), iat: Math.floor(Date.now() / 1000) }));
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${head}.${body}`)));
  jwt = `${head}.${body}.${b64url(sig)}`; jwtAt = Date.now();
  return jwt;
}

// a link to the small picture that works for one day, so the notification can show it
async function pictureLink(path: string | null) {
  if (!path) return null;
  const r = await db(`/storage/v1/object/sign/media/${path}`, { method: "POST", body: JSON.stringify({ expiresIn: 86400 }) });
  if (!r.ok) return null;
  const j = await r.json();
  const u = j.signedURL || j.signedUrl;
  return u ? `${SB_URL}/storage/v1${u.startsWith("/") ? u : "/" + u}` : null;
}

async function sendTo(member: { id: string; push_token: string }, msg: Record<string, unknown>, collapse?: string) {
  const headers: Record<string, string> = {
    authorization: `bearer ${await appleToken()}`,
    "apns-topic": BUNDLE,
    "apns-push-type": "alert",
    "apns-priority": "10",
  };
  if (collapse) headers["apns-collapse-id"] = collapse.slice(0, 64);
  const r = await fetch(`https://${HOST}/3/device/${member.push_token}`, { method: "POST", headers, body: JSON.stringify(msg) });
  if (r.status === 410 || r.status === 400) {
    const why = await r.text();
    // the phone deleted the app or the token is stale: stop sending to it
    if (r.status === 410 || why.includes("BadDeviceToken")) {
      await db(`/rest/v1/members?id=eq.${member.id}`, { method: "PATCH", body: JSON.stringify({ push_token: null }) });
    }
    return `${r.status} ${why}`;
  }
  return String(r.status);
}

const short = (s: string, n = 90) => (s && s.length > n ? s.slice(0, n - 1) + "…" : s || "");

Deno.serve(async (req) => {
  try {
    const { kind, id, hook } = await req.json();
    const secret = await one("hi_private", "key=eq.push_hook&select=value");
    if (!secret || !hook || hook !== secret.value) return new Response("no", { status: 403 });

    const isReply = kind === "reply";
    const row = await one(isReply ? "replies" : "posts", `id=eq.${id}&select=*`);
    if (!row) return new Response("gone", { status: 200 });
    const everyone = await many("members", `family_id=eq.${row.family_id}&select=id,name,role,push_token`);
    const members = everyone.filter((m: any) => m.push_token);
    // hearts, notes and "seen" come from people in Easy mode: use their names
    const easy = everyone.filter((m: any) => m.role === "gp").map((m: any) => m.name).filter(Boolean);
    const gp = easy.length ? easy.join(" & ") : "Someone";

    let to: typeof members = [], title = "", body = "", link = "hiello://home", picture = row.thumb_path, collapse: string | undefined;
    const what = row.media_kind === "video" ? "video" : "photo";

    if (kind === "post") {
      // a new hi: everyone else in the Circle
      to = members.filter((m: any) => m.id !== row.member_id);
      title = `${row.from_name || "Family"} sent you a hi`;
      body = short(row.note || row.caption || row.title) || (what === "video" ? "A video! Tap to watch ♥" : "Tap to see it ♥");
      link = `hiello://post/${row.id}`;
      if (row.kind === "recap") {
        // a Sunday Recap arrives as several photos: one notification that updates, not a ding per photo
        title = `${row.from_name || "Family"} sent you their week`;
        body = short(row.caption) || "A Sunday Recap ♥";
        collapse = `recap-${row.member_id}-${row.title}`;
      }
    } else if (kind === "reply") {
      to = members.filter((m: any) => m.id !== row.member_id);
      title = `${row.from_name || gp} sent you a hi`;
      body = short(row.note) || (row.media_kind ? `A ${what} back, just for you ♥` : "♥");
      if (!row.media_kind && (row.note || "").trim() === "♥") { title = `${row.from_name || "Someone"} ♥ your hi`; body = "Made their day."; }
      link = "hiello://reply/";
    } else {
      // someone in Easy mode did something with your hi: tell the person who sent it (one alert per photo, updated in place)
      to = members.filter((m: any) => m.id === row.member_id && m.role !== "gp");
      link = `hiello://post/${row.id}`;
      collapse = `p-${row.id}`;
      if (kind === "note") { title = `${gp} wrote on your hi`; body = `“${short(row.gp_note, 60)}”`; }
      else if (kind === "heart") { title = `${gp} ♥ your hi`; body = row.hearts > 1 ? `Loved it ${row.hearts} times!` : "Made their day."; }
      else if (kind === "rsvp") { title = row.rsvp === "yes" ? `${gp} will be there!` : `${gp} can’t make it`; body = row.rsvp === "yes" ? (short(row.title || row.note) || "Tap to see.") : "Send them a recap after ♥"; }
      else if (kind === "seen") { title = `${gp} just saw your hi ✓`; body = short(row.note || row.caption) || "Seen on the home screen."; }
      else return new Response("skip");
    }
    if (!to.length) return new Response("nobody");

    const image = await pictureLink(picture);
    const msg = {
      aps: { alert: { title, body }, sound: "default", "mutable-content": image ? 1 : 0, "thread-id": `hiello-${row.family_id}` },
      link, image,
    };
    const results = await Promise.all(to.map((m: any) => sendTo(m, msg, collapse)));
    return new Response(JSON.stringify(results), { headers: { "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(String(e), { status: 500 });
  }
});
