import { assertEquals } from 'jsr:@std/assert@1';
import { fakeDb } from '../_test/fake_db.ts';
import { handlePaystackWebhook } from './handler.ts';

const KEY = 'sk_test_123';
Deno.env.set('PAYSTACK_SECRET_KEY', KEY);

const pending = { id: 'pay-1', amount_cents: 150000, status: 'pending' };

async function sign(body: string, key = KEY) {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(key), { name: 'HMAC', hash: 'SHA-512' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(body));
  return Array.from(new Uint8Array(mac)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function post(event: unknown, signature?: string | null) {
  const body = JSON.stringify(event);
  const headers = new Headers();
  const sig = signature === undefined ? await sign(body) : signature;
  if (sig) headers.set('x-paystack-signature', sig);
  return new Request('http://x/paystack-webhook', { method: 'POST', body, headers });
}

const charge = (event = 'charge.success') => ({ event, data: { reference: 'pay-1' } });

function verifyResponse(data: Record<string, unknown>, ok = true): typeof fetch {
  return () => Promise.resolve(new Response(JSON.stringify({ data }), { status: ok ? 200 : 400 }));
}
const good = { status: 'success', amount: 150000, currency: 'KES', id: 987 };

Deno.test('rejects missing, wrong and forged signatures', async () => {
  const { db, rpcCalls } = fakeDb({ payment: pending });
  for (const sig of [null, 'deadbeef', await sign(JSON.stringify(charge()), 'other-key')]) {
    const res = await handlePaystackWebhook(await post(charge(), sig), () => db, verifyResponse(good));
    assertEquals(res.status, 401);
  }
  assertEquals(rpcCalls.length, 0);
});

Deno.test('rejects anything but POST', async () => {
  const { db } = fakeDb();
  const res = await handlePaystackWebhook(new Request('http://x/'), () => db);
  assertEquals(res.status, 405);
});

Deno.test('confirms the booking after Paystack verifies the transaction', async () => {
  const { db, rpcCalls } = fakeDb({ payment: pending });
  const res = await handlePaystackWebhook(await post(charge()), () => db, verifyResponse(good));
  assertEquals(res.status, 200);
  assertEquals(rpcCalls[0].name, 'confirm_booking_payment');
  assertEquals(rpcCalls[0].args.p_receipt, '987');
});

Deno.test('does not confirm when verification disagrees on amount, currency, status or HTTP result', async () => {
  const cases: [Record<string, unknown>, boolean][] = [
    [{ ...good, amount: 100 }, true],
    [{ ...good, currency: 'USD' }, true],
    [{ ...good, status: 'failed' }, true],
    [good, false],
  ];
  for (const [data, ok] of cases) {
    const { db, rpcCalls, updates } = fakeDb({ payment: pending });
    const res = await handlePaystackWebhook(await post(charge()), () => db, verifyResponse(data, ok));
    assertEquals(res.status, 200);
    assertEquals(rpcCalls.length, 0);
    assertEquals(updates[0].values.needs_review, true);
  }
});

Deno.test('returns 500 when confirmation fails so Paystack retries', async () => {
  const { db } = fakeDb({ payment: pending, rpcErrors: { confirm_booking_payment: { message: 'db down' } } });
  const res = await handlePaystackWebhook(await post(charge()), () => db, verifyResponse(good));
  assertEquals(res.status, 500);
});

Deno.test('marks the payment failed on charge.failed without calling Paystack', async () => {
  const { db, rpcCalls } = fakeDb({ payment: pending });
  const res = await handlePaystackWebhook(await post(charge('charge.failed')), () => db, () => {
    throw new Error('should not verify');
  });
  assertEquals(res.status, 200);
  assertEquals(rpcCalls.map((c) => c.name), ['mark_payment_failed']);
});

Deno.test('ignores payments that are not pending and unrelated events', async () => {
  const cases = [
    { payment: { ...pending, status: 'success' }, event: charge() },
    { payment: undefined, event: charge() },
    { payment: pending, event: charge('transfer.success') },
  ];
  for (const c of cases) {
    const { db, rpcCalls } = fakeDb({ payment: c.payment });
    const res = await handlePaystackWebhook(await post(c.event), () => db, verifyResponse(good));
    assertEquals(res.status, 200);
    assertEquals(rpcCalls.length, 0);
  }
});

Deno.test('refund.processed settles the matching processing refund', async () => {
  const { db, rpcCalls } = fakeDb({
    payment: { id: 'pay-1' },
    refunds: [{ id: 'ref-1', amount_cents: 50000, provider_ref: '555' }],
  });
  const event = { event: 'refund.processed', data: { transaction_reference: 'pay-1', amount: 50000, id: 555 } };
  const res = await handlePaystackWebhook(await post(event), () => db);
  assertEquals(res.status, 200);
  assertEquals(rpcCalls[0].name, 'finish_refund');
  assertEquals(rpcCalls[0].args, { p_refund_id: 'ref-1', p_status: 'processed', p_provider_ref: '555' });
});

Deno.test('refund.failed marks it failed, and an unmatched refund is ignored', async () => {
  const failed = { event: 'refund.failed', data: { transaction_reference: 'pay-1', amount: 50000, id: 555 } };
  const a = fakeDb({ payment: { id: 'pay-1' }, refunds: [{ id: 'ref-1', amount_cents: 50000, provider_ref: null }] });
  await handlePaystackWebhook(await post(failed), () => a.db);
  assertEquals(a.rpcCalls[0].args.p_status, 'failed');

  const b = fakeDb({ payment: { id: 'pay-1' }, refunds: [{ id: 'ref-2', amount_cents: 999, provider_ref: null }] });
  const res = await handlePaystackWebhook(await post(failed), () => b.db);
  assertEquals(res.status, 200);
  assertEquals(b.rpcCalls.length, 0);
});

Deno.test('a failing finish_refund returns 500 so Paystack retries', async () => {
  const { db } = fakeDb({
    payment: { id: 'pay-1' },
    refunds: [{ id: 'ref-1', amount_cents: 50000, provider_ref: null }],
    rpcErrors: { finish_refund: { message: 'boom' } },
  });
  const event = { event: 'refund.processed', data: { transaction_reference: 'pay-1', amount: 50000, id: 1 } };
  const res = await handlePaystackWebhook(await post(event), () => db);
  assertEquals(res.status, 500);
});
