// Receives the Daraja STK Push result. Daraja does not sign callbacks, so the URL carries a secret
// token, and the payment is matched by CheckoutRequestID and its amount before anything is confirmed.

import { json, requireEnv } from '../_shared/http.ts';
import { adminClient } from '../_shared/supabase.ts';

const ack = () => json({ ResultCode: 0, ResultDesc: 'Accepted' });

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const token = new URL(req.url).searchParams.get('token');
  if (token !== requireEnv('MPESA_CALLBACK_SECRET')) return json({ error: 'forbidden' }, 403);

  try {
    const payload = await req.json();
    const callback = payload?.Body?.stkCallback;
    if (!callback?.CheckoutRequestID) return ack();

    const db = adminClient();
    const { data: payment } = await db
      .from('payments')
      .select('id, amount_cents, status')
      .eq('provider', 'mpesa')
      .eq('reference', callback.CheckoutRequestID)
      .maybeSingle();
    if (!payment || payment.status !== 'pending') return ack();

    if (callback.ResultCode !== 0) {
      await db.rpc('mark_payment_failed', { p_payment_id: payment.id, p_raw: payload });
      return ack();
    }

    const items: { Name: string; Value?: string | number }[] = callback.CallbackMetadata?.Item ?? [];
    const amount = Number(items.find((i) => i.Name === 'Amount')?.Value);
    const receipt = String(items.find((i) => i.Name === 'MpesaReceiptNumber')?.Value ?? '');

    // The STK push was for whole shillings (rounded up), so compare against that.
    if (amount !== Math.ceil(payment.amount_cents / 100)) {
      console.error('mpesa amount mismatch', { payment: payment.id, amount });
      await db.from('payments').update({ needs_review: true, raw_payload: payload }).eq('id', payment.id);
      return ack();
    }

    const { error } = await db.rpc('confirm_booking_payment', {
      p_payment_id: payment.id,
      p_receipt: receipt,
      p_raw: payload,
    });
    if (error) throw error;
  } catch (e) {
    console.error('mpesa-callback failed', e);
  }
  return ack();
});
