// Sends pushes through Firebase Cloud Messaging HTTP v1 using the service account
// stored in the FCM_SERVICE_ACCOUNT secret. No Google SDK needed: we mint the
// OAuth token ourselves with WebCrypto.

type ServiceAccount = { client_email: string; private_key: string; project_id: string; token_uri?: string };

let cached: { token: string; exp: number } | null = null;

function b64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

export async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: sa.token_uri ?? "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const key = await importKey(sa.private_key);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  const res = await fetch(sa.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!res.ok) throw new Error(`token: ${res.status} ${await res.text()}`);
  const json = await res.json();
  cached = { token: json.access_token, exp: now + (json.expires_in ?? 3600) };
  return cached.token;
}

export type Push = { token: string; title: string; body: string; data: Record<string, string> };

/// Returns the list of tokens FCM reported as dead, so callers can remove them.
/// One phone that fails never stops the others. It throws, so the alert is
/// tried again, only when no phone at all was reached; otherwise a retry
/// would show the same alert twice on the phones that already have it.
export async function sendPushes(sa: ServiceAccount, pushes: Push[]): Promise<string[]> {
  const dead: string[] = [];
  if (pushes.length === 0) return dead;
  const bearer = await accessToken(sa);
  let ok = 0;
  const errors: string[] = [];
  await Promise.all(pushes.map(async (p) => {
    try {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { authorization: `Bearer ${bearer}`, "content-type": "application/json" },
        body: JSON.stringify({
          message: {
            token: p.token,
            notification: { title: p.title, body: p.body },
            data: p.data,
            android: { priority: "high", notification: { channel_id: "duebook_jobs", default_sound: true } },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      });
      if (res.ok) {
        await res.body?.cancel();
        ok++;
        return;
      }
      const text = await res.text();
      if (res.status === 404 || res.status === 410 || text.includes("UNREGISTERED")) dead.push(p.token);
      else errors.push(`fcm: ${res.status} ${text}`);
    } catch (e) {
      errors.push(String(e));
    }
  }));
  if (errors.length) {
    console.error("push failed", errors.length, "of", pushes.length, errors[0].slice(0, 300));
    if (ok === 0) throw new Error(errors[0]);
  }
  return dead;
}
