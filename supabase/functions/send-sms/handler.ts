// Delivers booking confirmations and reminders as SMS. pg_cron calls this every minute (see ..._sms_delivery_cron.sql).
// The rows are claimed first, so a failed send is not retried: the notification is still in the inbox and sent as push.

import { json, requireEnv } from '../_shared/http.ts';
import { normalizePhone } from '../_shared/africastalking.ts';

// deno-lint-ignore no-explicit-any
export type Db = any;

const BATCH = 50;

export async function handleSendSms(
  req: Request,
  getDb: () => Db,
  send: (to: string, message: string) => Promise<void>,
): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  if (req.headers.get('x-cron-secret') !== requireEnv('CRON_SECRET')) return json({ error: 'forbidden' }, 403);

  const { data: claimed, error } = await getDb().rpc('claim_unsmsed_notifications', { p_limit: BATCH });
  if (error) {
    console.error('send-sms claim failed', error);
    return json({ error: 'claim_failed' }, 500);
  }
  const counts = { texts: (claimed ?? []).length, sent: 0, skipped: 0, errors: 0 };
  for (const n of claimed ?? []) {
    const to = normalizePhone(n.phone);
    if (!to) {
      counts.skipped++;
      continue;
    }
    try {
      await send(to, [n.title, n.body].filter(Boolean).join(': '));
      counts.sent++;
    } catch (e) {
      console.error('send-sms send failed', n.id, e);
      counts.errors++;
    }
  }
  return json(counts);
}
