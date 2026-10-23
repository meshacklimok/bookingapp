// Starts a payment for a held booking. The amount always comes from the database, never the client.
//
// POST { booking_id, provider: 'mpesa' | 'paystack', phone?: string }
//  - mpesa:    sends an STK push to `phone`; the app then waits for the booking to become confirmed.
//  - paystack: returns { authorization_url } to open in the browser.

import { corsHeaders, json, requireEnv } from '../_shared/http.ts';
import { adminClient, userFromRequest } from '../_shared/supabase.ts';
import { normalizeKenyanPhone, stkPush } from '../_shared/mpesa.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const user = await userFromRequest(req);
    if (!user) return json({ error: 'unauthorized' }, 401);

    const { booking_id, provider, phone } = await req.json();
    if (!booking_id || (provider !== 'mpesa' && provider !== 'paystack')) {
      return json({ error: 'invalid_request' }, 400);
    }

    const db = adminClient();
    const { data: booking } = await db
      .from('bookings')
      .select('id, customer_id, org_id, status, expires_at, total_cents, services(title)')
      .eq('id', booking_id)
      .maybeSingle();

    if (!booking || booking.customer_id !== user.id) return json({ error: 'booking_not_found' }, 404);
    if (!['held', 'pending_payment'].includes(booking.status)) return json({ error: 'booking_not_payable' }, 409);
    if (booking.expires_at && new Date(booking.expires_at) < new Date()) return json({ error: 'hold_expired' }, 409);
    if (booking.total_cents <= 0) return json({ error: 'free_booking_unsupported' }, 400);

    const normalizedPhone = provider === 'mpesa' ? normalizeKenyanPhone(String(phone ?? '')) : null;
    if (provider === 'mpesa' && !normalizedPhone) return json({ error: 'invalid_phone' }, 400);

    const { data: payment, error: insertError } = await db
      .from('payments')
      .insert({
        booking_id: booking.id,
        customer_id: user.id,
        org_id: booking.org_id,
        provider,
        amount_cents: booking.total_cents,
        phone: normalizedPhone,
      })
      .select('id')
      .single();
    if (insertError) throw insertError;

    const title = (booking.services as { title?: string } | null)?.title ?? 'Booking';

    if (provider === 'mpesa') {
      const callbackUrl =
        `${requireEnv('SUPABASE_URL')}/functions/v1/mpesa-callback?token=${requireEnv('MPESA_CALLBACK_SECRET')}`;
      const { checkoutRequestId } = await stkPush({
        phone: normalizedPhone!,
        amountKes: Math.ceil(booking.total_cents / 100),
        accountReference: booking.id.replaceAll('-', ''),
        description: title,
        callbackUrl,
      });
      await db.from('payments').update({ reference: checkoutRequestId }).eq('id', payment.id);
      await db.from('bookings').update({ status: 'pending_payment' }).eq('id', booking.id);
      return json({ payment_id: payment.id, provider, checkout_request_id: checkoutRequestId });
    }

    // Paystack: our payment id is the reference, so the webhook can find the payment directly.
    const res = await fetch('https://api.paystack.co/transaction/initialize', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${requireEnv('PAYSTACK_SECRET_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: user.email ?? `${user.id}@users.invalid`,
        amount: booking.total_cents,
        currency: 'KES',
        reference: payment.id,
        metadata: { booking_id: booking.id, payment_id: payment.id },
      }),
    });
    const body = await res.json();
    if (!res.ok || !body.status) throw new Error(body.message ?? 'Paystack initialize failed');

    await db.from('payments').update({ reference: payment.id }).eq('id', payment.id);
    await db.from('bookings').update({ status: 'pending_payment' }).eq('id', booking.id);
    return json({
      payment_id: payment.id,
      provider,
      authorization_url: body.data.authorization_url,
    });
  } catch (e) {
    console.error('create-payment failed', e);
    return json({ error: e instanceof Error ? e.message : 'payment_failed' }, 500);
  }
});
