import { requireEnv } from './http.ts';

export type PushMessage = { title: string; body: string | null; data: Record<string, string> };
// `invalid` means FCM no longer knows the token (app uninstalled), so it should be deleted.
export type PushOutcome = 'ok' | 'invalid';

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

const b64url = (bytes: Uint8Array | string) => {
  const raw = typeof bytes === 'string' ? new TextEncoder().encode(bytes) : bytes;
  return btoa(String.fromCharCode(...raw)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
};

let cached: { token: string; expiresAt: number } | null = null;

// FCM HTTP v1 wants an OAuth token minted from the Firebase service account (FCM_SERVICE_ACCOUNT, the JSON key).
async function accessToken(account: ServiceAccount): Promise<string> {
  if (cached && cached.expiresAt > Date.now() + 60_000) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64url(JSON.stringify(claims))}`;
  const pem = account.private_key.replace(/-----[A-Z ]+-----/g, '').replace(/\s/g, '');
  const key = await crypto.subtle.importKey(
    'pkcs8',
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned)));
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${b64url(sig)}`,
    }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`Google OAuth failed (${res.status})`);
  cached = { token: body.access_token, expiresAt: Date.now() + body.expires_in * 1000 };
  return cached.token;
}

export async function sendPush(deviceToken: string, message: PushMessage): Promise<PushOutcome> {
  const account: ServiceAccount = JSON.parse(requireEnv('FCM_SERVICE_ACCOUNT'));
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${await accessToken(account)}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: {
        token: deviceToken,
        notification: { title: message.title, ...(message.body ? { body: message.body } : {}) },
        data: message.data,
      },
    }),
  });
  if (res.ok) return 'ok';
  const body = await res.json().catch(() => ({}));
  const status = body?.error?.status;
  if (status === 'NOT_FOUND' || status === 'UNREGISTERED') return 'invalid';
  throw new Error(`FCM send failed (${res.status} ${status ?? ''})`);
}
