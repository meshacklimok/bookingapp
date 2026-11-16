import { assertEquals } from 'jsr:@std/assert@1';
import { fakeDb } from '../_test/fake_db.ts';
import type { StkStatus } from '../_shared/mpesa.ts';
import { handleMpesaReconcile } from './handler.ts';

Deno.env.set('CRON_SECRET', 'cr0n');

const pending = [
  { id: 'pay-1', reference: 'ws_CO_1' },
  { id: 'pay-2', reference: 'ws_CO_2' },
];

function post(secret = 'cr0n') {
  return new Request('http://x/mpesa-reconcile', { method: 'POST', headers: { 'x-cron-secret': secret } });
}

function answers(byReference: Record<string, StkStatus | Error>) {
  const asked: string[] = [];
  const query = (ref: string) => {
    asked.push(ref);
    const a = byReference[ref];
    return a instanceof Error ? Promise.reject(a) : Promise.resolve(a);
  };
  return { query, asked };
}

const done = (resultCode: string): StkStatus => ({ state: 'done', resultCode, raw: { ResultCode: resultCode } });

Deno.test('rejects anything but POST', async () => {
  const { db } = fakeDb();
  const { query, asked } = answers({});
  const res = await handleMpesaReconcile(new Request('http://x/'), () => db, query);
  assertEquals(res.status, 405);
  assertEquals(asked.length, 0);
});

Deno.test('rejects a wrong or missing cron secret without asking Daraja', async () => {
  const { db, rpcCalls } = fakeDb({ payments: pending });
  const { query, asked } = answers({});
  for (const secret of ['nope', '']) {
    const res = await handleMpesaReconcile(post(secret), () => db, query);
    assertEquals(res.status, 403);
  }
  assertEquals(asked.length + rpcCalls.length, 0);
});

Deno.test('confirms a payment Daraja reports as paid, without a receipt', async () => {
  const { db, rpcCalls } = fakeDb({ payments: [pending[0]] });
  const { query } = answers({ ws_CO_1: done('0') });
  const res = await handleMpesaReconcile(post(), () => db, query);
  assertEquals(res.status, 200);
  assertEquals(rpcCalls.length, 1);
  assertEquals(rpcCalls[0].name, 'confirm_booking_payment');
  assertEquals(rpcCalls[0].args.p_payment_id, 'pay-1');
  assertEquals(rpcCalls[0].args.p_receipt, null);
  assertEquals(rpcCalls[0].args.p_raw.source, 'stk_query');
});

Deno.test('fails a payment the customer cancelled or that timed out', async () => {
  const { db, rpcCalls } = fakeDb({ payments: pending });
  const { query } = answers({ ws_CO_1: done('1032'), ws_CO_2: done('1037') });
  const res = await handleMpesaReconcile(post(), () => db, query);
  assertEquals(await res.json(), { confirmed: 0, failed: 2, processing: 0, errors: 0 });
  assertEquals(rpcCalls.map((c) => c.name), ['mark_payment_failed', 'mark_payment_failed']);
});

Deno.test('leaves a payment alone while the customer has not answered yet', async () => {
  const { db, rpcCalls } = fakeDb({ payments: [pending[0]] });
  const { query } = answers({ ws_CO_1: { state: 'processing' } });
  const res = await handleMpesaReconcile(post(), () => db, query);
  assertEquals((await res.json()).processing, 1);
  assertEquals(rpcCalls.length, 0);
});

Deno.test('one failing query does not stop the others', async () => {
  const { db, rpcCalls } = fakeDb({ payments: pending });
  const { query, asked } = answers({ ws_CO_1: new Error('daraja down'), ws_CO_2: done('0') });
  const res = await handleMpesaReconcile(post(), () => db, query);
  assertEquals(res.status, 200);
  assertEquals(asked, ['ws_CO_1', 'ws_CO_2']);
  assertEquals(await res.json(), { confirmed: 1, failed: 0, processing: 0, errors: 1 });
  assertEquals(rpcCalls[0].args.p_payment_id, 'pay-2');
});

Deno.test('counts a database error as an error, to be retried next run', async () => {
  const { db } = fakeDb({ payments: [pending[0]], rpcErrors: { confirm_booking_payment: new Error('boom') } });
  const { query } = answers({ ws_CO_1: done('0') });
  const res = await handleMpesaReconcile(post(), () => db, query);
  assertEquals((await res.json()).errors, 1);
});

Deno.test('does nothing when no payments are waiting', async () => {
  const { db, rpcCalls } = fakeDb({ payments: [] });
  const { query, asked } = answers({});
  const res = await handleMpesaReconcile(post(), () => db, query);
  assertEquals(res.status, 200);
  assertEquals(asked.length + rpcCalls.length, 0);
});
