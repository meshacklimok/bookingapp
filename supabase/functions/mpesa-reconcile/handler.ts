// Settles M-Pesa payments whose STK callback never arrived. pg_cron calls this every minute
// (see ..._mpesa_reconcile_cron.sql); it asks Daraja about each payment still pending after
// two minutes and confirms or fails it the same way mpesa-callback would.

import { json, requireEnv } from '../_shared/http.ts';
import type { StkStatus } from '../_shared/mpesa.ts';

// deno-lint-ignore no-explicit-any
export type Db = any;

// Daraja normally calls back within a minute; give it that chance before asking.
const GRACE_MS = 2 * 60 * 1000;
// Stop asking after a day. Anything older is left for an admin to look at.
const GIVE_UP_MS = 24 * 3600 * 1000;
const BATCH = 20;

export async function handleMpesaReconcile(
  req: Request,
  getDb: () => Db,
  query: (checkoutRequestId: string) => Promise<StkStatus>,
  now = Date.now(),
): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  if (req.headers.get('x-cron-secret') !== requireEnv('CRON_SECRET')) return json({ error: 'forbidden' }, 403);

  const db = getDb();
  const { data: payments, error } = await db
    .from('payments')
    .select('id, reference')
    .eq('provider', 'mpesa')
    .eq('status', 'pending')
    .not('reference', 'is', null)
    .lt('created_at', new Date(now - GRACE_MS).toISOString())
    .gt('created_at', new Date(now - GIVE_UP_MS).toISOString())
    .order('created_at')
    .limit(BATCH);
  if (error) {
    console.error('mpesa-reconcile lookup failed', error);
    return json({ error: 'lookup_failed' }, 500);
  }

  const counts = { confirmed: 0, failed: 0, processing: 0, errors: 0 };
  for (const payment of payments ?? []) {
    try {
      const status = await query(payment.reference);
      if (status.state === 'processing') {
        counts.processing++;
        continue;
      }
      const raw = { source: 'stk_query', ...status.raw };
      // No receipt or amount comes back from the query; the push itself was for the stored amount.
      const { error: rpcError } = status.resultCode === '0'
        ? await db.rpc('confirm_booking_payment', { p_payment_id: payment.id, p_receipt: null, p_raw: raw })
        : await db.rpc('mark_payment_failed', { p_payment_id: payment.id, p_raw: raw });
      if (rpcError) throw rpcError;
      if (status.resultCode === '0') counts.confirmed++;
      else counts.failed++;
    } catch (e) {
      // One bad payment must not block the rest; it is retried on the next run.
      console.error('mpesa-reconcile payment failed', payment.id, e);
      counts.errors++;
    }
  }
  return json(counts);
}
