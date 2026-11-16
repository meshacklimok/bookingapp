import { assertEquals } from 'jsr:@std/assert@1';
import { handleProcessRefund } from './handler.ts';

// deno-lint-ignore no-explicit-any
type Row = any;

function refundRow(id: string, provider: string, over: Row = {}) {
  return {
    id,
    amount_cents: 50_000,
    status: 'pending',
    payment_id: 'pay-1',
    payments: { id: 'pay-1', provider, reference: provider === 'paystack' ? 'ref-1' : 'ws_CO_1', customer_id: 'cust', org_id: 'org', booking_id: 'b1' },
    ...over,
  };
}

// A chainable stand-in for the service-role client. Every filter is a no-op; tables answer with canned rows.
function fakeDb(opts: { admin?: boolean; member?: boolean; refunds?: Row[]; claimable?: boolean } = {}) {
  const updates: { values: Row }[] = [];
  const rpcs: { name: string; args: Row }[] = [];
  const db = {
    from(table: string) {
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: () => q,
        in: () => q,
        maybeSingle: () =>
          Promise.resolve({
            data: table === 'profiles' ? { is_platform_admin: opts.admin === true } : opts.member ? { role: 'owner' } : null,
          }),
        // deno-lint-ignore no-explicit-any
        then: (resolve: any) => {
          return resolve({ data: opts.refunds ?? [], error: null });
        },
        update: (values: Row) => {
          updates.push({ values });
          // the claim ends in .select(); the other updates are just awaited
          const u: Row = { eq: () => u, then: (resolve: Row) => resolve({ error: null }) };
          u.select = () => Promise.resolve({ data: opts.claimable === false ? [] : [{ id: 'x' }] });
          return u;
        },
      };
      return q;
    },
    rpc(name: string, args: Row) {
      rpcs.push({ name, args });
      return Promise.resolve({ error: null });
    },
  };
  return { db, updates, rpcs };
}

const post = (body: unknown) =>
  new Request('http://x/process-refund', { method: 'POST', headers: { Authorization: 'Bearer t' }, body: JSON.stringify(body) });
const signedIn = () => Promise.resolve({ id: 'cust' });
const nobody = () => Promise.resolve(null);
const neverRefund = () => Promise.reject(new Error('should not call Paystack'));

Deno.test('rejects anything but POST', async () => {
  const { db } = fakeDb();
  const res = await handleProcessRefund(new Request('http://x/'), () => db, signedIn, neverRefund);
  assertEquals(res.status, 405);
});

Deno.test('rejects anonymous callers and empty requests', async () => {
  const { db } = fakeDb();
  assertEquals((await handleProcessRefund(post({ booking_id: 'b1' }), () => db, nobody, neverRefund)).status, 401);
  assertEquals((await handleProcessRefund(post({}), () => db, signedIn, neverRefund)).status, 400);
});

Deno.test('only platform admins may retry a single refund', async () => {
  const { db } = fakeDb({ refunds: [refundRow('r1', 'paystack')] });
  const res = await handleProcessRefund(post({ refund_id: 'r1' }), () => db, signedIn, neverRefund);
  assertEquals(res.status, 403);
});

Deno.test('a stranger cannot refund someone else\'s booking', async () => {
  const { db } = fakeDb({ refunds: [refundRow('r1', 'paystack')] });
  const res = await handleProcessRefund(post({ booking_id: 'b1' }), () => db, () => Promise.resolve({ id: 'stranger' }), neverRefund);
  assertEquals(res.status, 403);
});

Deno.test('returns no results when nothing is pending', async () => {
  const { db } = fakeDb({ refunds: [] });
  const res = await handleProcessRefund(post({ booking_id: 'b1' }), () => db, signedIn, neverRefund);
  assertEquals(await res.json(), { results: [] });
});

Deno.test('M-Pesa refunds are left for an admin to send by hand', async () => {
  const { db, updates } = fakeDb({ refunds: [refundRow('r1', 'mpesa')] });
  const res = await handleProcessRefund(post({ booking_id: 'b1' }), () => db, signedIn, neverRefund);
  assertEquals((await res.json()).results, [{ refund_id: 'r1', outcome: 'manual' }]);
  assertEquals(updates.length, 0);
});

Deno.test('a Paystack refund is claimed and sent for the stored amount', async () => {
  const { db, updates } = fakeDb({ refunds: [refundRow('r1', 'paystack')] });
  let sent: Row = null;
  const res = await handleProcessRefund(post({ booking_id: 'b1', amount_cents: 1 }), () => db, signedIn, (p) => {
    sent = p;
    return Promise.resolve({ status: 'pending', id: 'p-9' });
  });
  assertEquals((await res.json()).results, [{ refund_id: 'r1', outcome: 'processing' }]);
  assertEquals(sent.amountCents, 50_000);
  assertEquals(sent.transactionReference, 'ref-1');
  assertEquals(updates[0].values.status, 'processing');
  assertEquals(updates[1].values.provider_ref, 'p-9');
});

Deno.test('a refund someone else already claimed is skipped, not sent twice', async () => {
  const { db } = fakeDb({ refunds: [refundRow('r1', 'paystack')], claimable: false });
  const res = await handleProcessRefund(post({ booking_id: 'b1' }), () => db, signedIn, neverRefund);
  assertEquals((await res.json()).results, [{ refund_id: 'r1', outcome: 'skipped' }]);
});

Deno.test('an immediately processed or failed refund is finished through the database', async () => {
  for (const status of ['processed', 'failed']) {
    const { db, rpcs } = fakeDb({ refunds: [refundRow('r1', 'paystack')] });
    const res = await handleProcessRefund(post({ booking_id: 'b1' }), () => db, signedIn, () => Promise.resolve({ status, id: 'p-1' }));
    assertEquals(rpcs[0].name, 'finish_refund');
    assertEquals(rpcs[0].args.p_status, status);
    assertEquals((await res.json()).results[0].outcome, status === 'processed' ? 'processed' : 'error');
  }
});

Deno.test('a failed request puts the refund back to pending with the error', async () => {
  const { db, updates } = fakeDb({ refunds: [refundRow('r1', 'paystack')] });
  const res = await handleProcessRefund(post({ booking_id: 'b1' }), () => db, signedIn, () => Promise.reject(new Error('network down')));
  assertEquals((await res.json()).results, [{ refund_id: 'r1', outcome: 'error', error: 'network down' }]);
  assertEquals(updates.at(-1)!.values, { status: 'pending', last_error: 'network down' });
});

Deno.test('org owners and platform admins pass the permission check', async () => {
  for (const opts of [{ member: true }, { admin: true }]) {
    const { db } = fakeDb({ ...opts, refunds: [refundRow('r1', 'mpesa')] });
    const res = await handleProcessRefund(post({ booking_id: 'b1' }), () => db, () => Promise.resolve({ id: 'someone' }), neverRefund);
    assertEquals(res.status, 200);
  }
});
