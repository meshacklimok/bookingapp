// Receives Paystack webhooks. The HMAC signature is checked, then the transaction is re-verified
// with Paystack's API before the booking is confirmed.

import { json, requireEnv } from '../_shared/http.ts';
import { adminClient } from '../_shared/supabase.ts';

async function validSignature(rawBody: string, signature: string | null): Promise<boolean> {
  if (!signature) return false;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(requireEnv('PAYSTACK_SECRET_KEY')),
    { name: 'HMAC', hash: 'SHA-512' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  const expected = Array.from(new Uint8Array(mac)).map((b) => b.toString(16).padStart(2, '0')).join('');
  return expected === signature;
}

// refund.processed / refund.failed settle a refund that process-refund left `processing`. Paystack identifies the
// refund by its own id and by the transaction reference (our payment id), so match on the payment and the amount.
async function handleRefundEvent(event: { event: string; data?: Record<string, unknown> }) {
  if (event.event !== 'refund.processed' && event.event !== 'refund.failed') return;
  const transaction = event.data?.transaction_reference ?? event.data?.transaction;
  if (typeof transaction !== 'string') return;
  const amount = Number(event.data?.amount);
  const providerRef = event.data?.id != null ? String(event.data.id) : null;

  const db = adminClient();
  const { data: payment } = await db
    .from('payments')
    .select('id')
    .eq('provider', 'paystack')
    .eq('reference', transaction)
    .maybeSingle();
  if (!payment) return;

  const { data: processing } = await db
    .from('refunds')
    .select('id, amount_cents, provider_ref')
    .eq('payment_id', payment.id)
    .eq('status', 'processing');
  const match = (processing ?? []).find((r) => providerRef != null && r.provider_ref === providerRef) ??
    (processing ?? []).find((r) => r.amount_cents === amount);
  if (!match) return;

  const { error } = await db.rpc('finish_refund', {
    p_refund_id: match.id,
    p_status: event.event === 'refund.processed' ? 'processed' : 'failed',
    p_provider_ref: providerRef,
  });
  if (error) throw error;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const rawBody = await req.text();
  if (!(await validSignature(rawBody, req.headers.get('x-paystack-signature')))) {
    return json({ error: 'invalid_signature' }, 401);
  }

  try {
    const event = JSON.parse(rawBody);
    if (typeof event?.event === 'string' && event.event.startsWith('refund.')) {
      await handleRefundEvent(event);
      return json({ received: true });
    }
    const reference: string | undefined = event?.data?.reference;
    if (!reference) return json({ received: true });

    const db = adminClient();
    const { data: payment } = await db
      .from('payments')
      .select('id, amount_cents, status')
      .eq('provider', 'paystack')
      .eq('reference', reference)
      .maybeSingle();
    if (!payment || payment.status !== 'pending') return json({ received: true });

    if (event.event === 'charge.failed') {
      await db.rpc('mark_payment_failed', { p_payment_id: payment.id, p_raw: event });
      return json({ received: true });
    }
    if (event.event !== 'charge.success') return json({ received: true });

    const verifyRes = await fetch(
      `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
      { headers: { Authorization: `Bearer ${requireEnv('PAYSTACK_SECRET_KEY')}` } },
    );
    const verified = await verifyRes.json();
    if (
      !verifyRes.ok ||
      verified?.data?.status !== 'success' ||
      verified.data.amount !== payment.amount_cents ||
      verified.data.currency !== 'KES'
    ) {
      console.error('paystack verification mismatch', { payment: payment.id });
      await db.from('payments').update({ needs_review: true, raw_payload: event }).eq('id', payment.id);
      return json({ received: true });
    }

    const { error } = await db.rpc('confirm_booking_payment', {
      p_payment_id: payment.id,
      p_receipt: String(verified.data.id ?? reference),
      p_raw: event,
    });
    if (error) throw error;
  } catch (e) {
    console.error('paystack-webhook failed', e);
    // Non-2xx makes Paystack retry the webhook later.
    return json({ error: 'processing_failed' }, 500);
  }
  return json({ received: true });
});
