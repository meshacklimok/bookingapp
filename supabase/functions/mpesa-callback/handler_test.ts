import { assertEquals } from 'jsr:@std/assert@1';
import { fakeDb } from '../_test/fake_db.ts';
import { handleMpesaCallback } from './handler.ts';

Deno.env.set('MPESA_CALLBACK_SECRET', 's3cret');

const pending = { id: 'pay-1', amount_cents: 150000, status: 'pending' };

function callback(resultCode: number, amount = 1500) {
  return {
    Body: {
      stkCallback: {
        CheckoutRequestID: 'ws_CO_1',
        ResultCode: resultCode,
        CallbackMetadata: resultCode === 0
          ? { Item: [{ Name: 'Amount', Value: amount }, { Name: 'MpesaReceiptNumber', Value: 'QWE123' }] }
          : undefined,
      },
    },
  };
}

function post(body: unknown, token = 's3cret') {
  return new Request(`http://x/mpesa-callback?token=${token}`, { method: 'POST', body: JSON.stringify(body) });
}

Deno.test('rejects anything but POST', async () => {
  const { db } = fakeDb();
  const res = await handleMpesaCallback(new Request('http://x/?token=s3cret'), () => db);
  assertEquals(res.status, 405);
});

Deno.test('rejects a wrong or missing token without touching the database', async () => {
  const { db, rpcCalls, updates } = fakeDb({ payment: pending });
  for (const token of ['nope', '']) {
    const res = await handleMpesaCallback(post(callback(0), token), () => db);
    assertEquals(res.status, 403);
  }
  assertEquals(rpcCalls.length + updates.length, 0);
});

Deno.test('confirms the booking with the M-Pesa receipt', async () => {
  const { db, rpcCalls } = fakeDb({ payment: pending });
  const res = await handleMpesaCallback(post(callback(0)), () => db);
  assertEquals(res.status, 200);
  assertEquals(rpcCalls.length, 1);
  assertEquals(rpcCalls[0].name, 'confirm_booking_payment');
  assertEquals(rpcCalls[0].args.p_payment_id, 'pay-1');
  assertEquals(rpcCalls[0].args.p_receipt, 'QWE123');
});

Deno.test('does not confirm when the paid amount differs, and flags the payment for review', async () => {
  const { db, rpcCalls, updates } = fakeDb({ payment: pending });
  const res = await handleMpesaCallback(post(callback(0, 1)), () => db);
  assertEquals(res.status, 200);
  assertEquals(rpcCalls.length, 0);
  assertEquals(updates[0].values.needs_review, true);
});

Deno.test('rounds the expected amount up to whole shillings', async () => {
  const { db, rpcCalls } = fakeDb({ payment: { ...pending, amount_cents: 150050 } });
  await handleMpesaCallback(post(callback(0, 1501)), () => db);
  assertEquals(rpcCalls[0].name, 'confirm_booking_payment');
});

Deno.test('marks the payment failed when the customer cancels or the push fails', async () => {
  const { db, rpcCalls } = fakeDb({ payment: pending });
  const res = await handleMpesaCallback(post(callback(1032)), () => db);
  assertEquals(res.status, 200);
  assertEquals(rpcCalls.map((c) => c.name), ['mark_payment_failed']);
});

Deno.test('ignores payments that are not pending (duplicate callback) and unknown references', async () => {
  for (const payment of [{ ...pending, status: 'success' }, undefined]) {
    const { db, rpcCalls } = fakeDb({ payment });
    const res = await handleMpesaCallback(post(callback(0)), () => db);
    assertEquals(res.status, 200);
    assertEquals(rpcCalls.length, 0);
  }
});

Deno.test('returns 500 when confirmation fails so Daraja retries', async () => {
  const { db } = fakeDb({ payment: pending, rpcErrors: { confirm_booking_payment: { message: 'db down' } } });
  const res = await handleMpesaCallback(post(callback(0)), () => db);
  assertEquals(res.status, 500);
});

Deno.test('acknowledges a payload with no CheckoutRequestID', async () => {
  const { db, rpcCalls } = fakeDb();
  const res = await handleMpesaCallback(post({ Body: {} }), () => db);
  assertEquals(res.status, 200);
  assertEquals(rpcCalls.length, 0);
});
