// Sends pending refunds back through the provider.
//
// POST { booking_id } or { refund_id }
//  - booking_id: every pending refund of that booking. Allowed for its customer, its organization's owners and
//    admins, and platform admins (the app calls this right after a cancellation).
//  - refund_id: one refund. Platform admins only (retry from the admin screen).
//
// Amounts come from the database. Paystack refunds are asynchronous: the refund becomes `processing` here and
// `processed` or `failed` in paystack-webhook. M-Pesa cannot refund part of a payment through an API call, so
// those refunds stay `pending` for an admin to send by hand and record with resolve_refund.

import { corsHeaders, json } from '../_shared/http.ts';
import { adminClient, userFromRequest } from '../_shared/supabase.ts';
import { createPaystackRefund } from '../_shared/paystack.ts';

type Result = { refund_id: string; outcome: 'processing' | 'processed' | 'manual' | 'skipped' | 'error'; error?: string };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const user = await userFromRequest(req);
    if (!user) return json({ error: 'unauthorized' }, 401);

    const { booking_id, refund_id } = await req.json();
    if (!booking_id && !refund_id) return json({ error: 'invalid_request' }, 400);

    const db = adminClient();
    const { data: profile } = await db.from('profiles').select('is_platform_admin').eq('id', user.id).maybeSingle();
    const isAdmin = profile?.is_platform_admin === true;
    if (refund_id && !isAdmin) return json({ error: 'forbidden' }, 403);

    let query = db
      .from('refunds')
      .select('id, amount_cents, status, payment_id, payments!inner(id, provider, reference, customer_id, org_id, booking_id)')
      .eq('status', 'pending');
    query = refund_id ? query.eq('id', refund_id) : query.eq('payments.booking_id', booking_id);
    const { data: refunds, error } = await query;
    if (error) throw error;
    if (!refunds || refunds.length === 0) return json({ results: [] });

    if (!isAdmin) {
      const payment = refunds[0].payments as unknown as { customer_id: string; org_id: string };
      let allowed = payment.customer_id === user.id;
      if (!allowed) {
        const { data: member } = await db
          .from('org_members')
          .select('role')
          .eq('org_id', payment.org_id)
          .eq('user_id', user.id)
          .in('role', ['owner', 'admin'])
          .maybeSingle();
        allowed = member != null;
      }
      if (!allowed) return json({ error: 'forbidden' }, 403);
    }

    const results: Result[] = [];
    for (const r of refunds) {
      const payment = r.payments as unknown as { provider: string; reference: string | null };
      if (payment.provider !== 'paystack' || !payment.reference) {
        results.push({ refund_id: r.id, outcome: 'manual' });
        continue;
      }

      // Claim it so a double tap or a retry cannot send the money twice.
      const { data: claimed } = await db
        .from('refunds')
        .update({ status: 'processing', last_error: null })
        .eq('id', r.id)
        .eq('status', 'pending')
        .select('id');
      if (!claimed || claimed.length === 0) {
        results.push({ refund_id: r.id, outcome: 'skipped' });
        continue;
      }

      try {
        const out = await createPaystackRefund({
          transactionReference: payment.reference,
          amountCents: r.amount_cents,
          note: `refund ${r.id}`,
        });
        if (out.id) await db.from('refunds').update({ provider_ref: out.id }).eq('id', r.id);
        if (out.status === 'processed') {
          await db.rpc('finish_refund', { p_refund_id: r.id, p_status: 'processed', p_provider_ref: out.id });
          results.push({ refund_id: r.id, outcome: 'processed' });
        } else if (out.status === 'failed') {
          await db.rpc('finish_refund', { p_refund_id: r.id, p_status: 'failed', p_provider_ref: out.id });
          results.push({ refund_id: r.id, outcome: 'error', error: 'Paystack rejected the refund' });
        } else {
          results.push({ refund_id: r.id, outcome: 'processing' });
        }
      } catch (e) {
        // The request itself failed (nothing was sent), so put it back for a retry.
        const message = e instanceof Error ? e.message : 'refund_failed';
        console.error('process-refund failed', r.id, e);
        await db.from('refunds').update({ status: 'pending', last_error: message }).eq('id', r.id);
        results.push({ refund_id: r.id, outcome: 'error', error: message });
      }
    }
    return json({ results });
  } catch (e) {
    console.error('process-refund failed', e);
    return json({ error: e instanceof Error ? e.message : 'refund_failed' }, 500);
  }
});
