// Delivers notification rows as push messages. pg_cron calls this every minute (see ..._push_delivery.sql). The rows
// are claimed first, so a failed send is not retried: the notification is still in the in-app inbox.

import { json, requireEnv } from '../_shared/http.ts';
import type { PushMessage, PushOutcome } from '../_shared/fcm.ts';

// deno-lint-ignore no-explicit-any
export type Db = any;

const BATCH = 50;

export async function handleSendPush(
  req: Request,
  getDb: () => Db,
  send: (deviceToken: string, message: PushMessage) => Promise<PushOutcome>,
): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  if (req.headers.get('x-cron-secret') !== requireEnv('CRON_SECRET')) return json({ error: 'forbidden' }, 403);

  const db = getDb();
  const { data: claimed, error } = await db.rpc('claim_unpushed_notifications', { p_limit: BATCH });
  if (error) {
    console.error('send-push claim failed', error);
    return json({ error: 'claim_failed' }, 500);
  }
  const notifications = claimed ?? [];
  const counts = { notifications: notifications.length, sent: 0, removed_tokens: 0, errors: 0 };
  if (notifications.length === 0) return json(counts);

  const userIds = [...new Set(notifications.map((n: { user_id: string }) => n.user_id))];
  const { data: tokens, error: tokenError } = await db.from('device_tokens').select('user_id, token').in('user_id', userIds);
  if (tokenError) {
    console.error('send-push token lookup failed', tokenError);
    return json({ error: 'lookup_failed' }, 500);
  }

  for (const n of notifications) {
    // FCM data values must all be strings.
    const data = Object.fromEntries(Object.entries(n.data ?? {}).map(([k, v]) => [k, String(v)]));
    for (const t of (tokens ?? []).filter((t: { user_id: string }) => t.user_id === n.user_id)) {
      try {
        const outcome = await send(t.token, { title: n.title, body: n.body, data });
        if (outcome === 'ok') {
          counts.sent++;
        } else {
          await db.from('device_tokens').delete().eq('token', t.token);
          counts.removed_tokens++;
        }
      } catch (e) {
        console.error('send-push send failed', n.id, e);
        counts.errors++;
      }
    }
  }
  return json(counts);
}
