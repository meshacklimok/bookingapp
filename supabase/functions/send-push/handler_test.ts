import { assertEquals } from 'jsr:@std/assert@1';
import type { PushMessage, PushOutcome } from '../_shared/fcm.ts';
import { handleSendPush } from './handler.ts';

Deno.env.set('CRON_SECRET', 'cr0n');

const notes = [
  { id: 'n1', user_id: 'u1', title: 'Booking confirmed', body: 'Haircut', data: { route: '/bookings', n: 3 } },
  { id: 'n2', user_id: 'u2', title: 'Coming up', body: null, data: null },
];
const tokens = [
  { user_id: 'u1', token: 'phone-a' },
  { user_id: 'u1', token: 'phone-b' },
  { user_id: 'u3', token: 'someone-else' },
];

function fakeDb(claimed = notes) {
  const claims: unknown[] = [];
  const deleted: string[] = [];
  const db = {
    rpc(name: string, args: unknown) {
      claims.push({ name, args });
      return Promise.resolve({ data: claimed, error: null });
    },
    from(table: string) {
      return {
        select: () => ({ in: () => Promise.resolve({ data: table === 'device_tokens' ? tokens : [] }) }),
        delete: () => ({
          eq: (_c: string, token: string) => {
            deleted.push(token);
            return Promise.resolve({ error: null });
          },
        }),
      };
    },
  };
  return { db, claims, deleted };
}

const post = (secret = 'cr0n') =>
  new Request('http://x/send-push', { method: 'POST', headers: { 'x-cron-secret': secret } });

Deno.test('rejects anything but POST with the right cron secret', async () => {
  const { db, claims } = fakeDb();
  const send = () => Promise.resolve('ok' as PushOutcome);
  assertEquals((await handleSendPush(new Request('http://x/'), () => db, send)).status, 405);
  assertEquals((await handleSendPush(post('nope'), () => db, send)).status, 403);
  assertEquals(claims.length, 0);
});

Deno.test('pushes each notification to every device of its user only, with string data', async () => {
  const { db } = fakeDb();
  const sent: { token: string; message: PushMessage }[] = [];
  const res = await handleSendPush(post(), () => db, (token, message) => {
    sent.push({ token, message });
    return Promise.resolve('ok');
  });
  assertEquals(await res.json(), { notifications: 2, sent: 2, removed_tokens: 0, errors: 0 });
  assertEquals(sent.map((s) => s.token), ['phone-a', 'phone-b']);
  assertEquals(sent[0].message.data, { route: '/bookings', n: '3' });
});

Deno.test('deletes tokens FCM no longer knows and survives a failing send', async () => {
  const { db, deleted } = fakeDb();
  const res = await handleSendPush(post(), () => db, (token) =>
    token === 'phone-a' ? Promise.resolve('invalid') : Promise.reject(new Error('boom')));
  assertEquals(await res.json(), { notifications: 2, sent: 0, removed_tokens: 1, errors: 1 });
  assertEquals(deleted, ['phone-a']);
});

Deno.test('does nothing when the queue is empty', async () => {
  const { db } = fakeDb([]);
  const res = await handleSendPush(post(), () => db, () => Promise.reject(new Error('should not send')));
  assertEquals(await res.json(), { notifications: 0, sent: 0, removed_tokens: 0, errors: 0 });
});
