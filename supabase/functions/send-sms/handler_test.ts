import { assertEquals } from 'jsr:@std/assert@1';
import { normalizePhone } from '../_shared/africastalking.ts';
import { handleSendSms } from './handler.ts';

Deno.env.set('CRON_SECRET', 'cr0n');

const rows = [
  { id: 'n1', phone: '0712345678', title: 'Booking confirmed', body: 'Haircut on Mon 26 Oct, 10:00.' },
  { id: 'n2', phone: 'not a number', title: 'Coming up', body: null },
  { id: 'n3', phone: '+254722000111', title: 'Coming up', body: 'Massage' },
];

const fakeDb = (data = rows) => {
  const calls: string[] = [];
  return { calls, db: { rpc: (name: string) => (calls.push(name), Promise.resolve({ data, error: null })) } };
};
const post = (secret = 'cr0n') => new Request('http://x/send-sms', { method: 'POST', headers: { 'x-cron-secret': secret } });

Deno.test('rejects anything but POST with the right cron secret', async () => {
  const { db, calls } = fakeDb();
  const send = () => Promise.resolve();
  assertEquals((await handleSendSms(new Request('http://x/'), () => db, send)).status, 405);
  assertEquals((await handleSendSms(post('nope'), () => db, send)).status, 403);
  assertEquals(calls.length, 0);
});

Deno.test('texts normalized numbers, skips unusable ones and survives a failing send', async () => {
  const { db } = fakeDb();
  const sent: [string, string][] = [];
  const res = await handleSendSms(post(), () => db, (to, message) => {
    sent.push([to, message]);
    return to.endsWith('111') ? Promise.reject(new Error('boom')) : Promise.resolve();
  });
  assertEquals(await res.json(), { texts: 3, sent: 1, skipped: 1, errors: 1 });
  assertEquals(sent[0], ['+254712345678', 'Booking confirmed: Haircut on Mon 26 Oct, 10:00.']);
});

Deno.test('does nothing when the queue is empty', async () => {
  const { db } = fakeDb([]);
  const res = await handleSendSms(post(), () => db, () => Promise.reject(new Error('should not send')));
  assertEquals(await res.json(), { texts: 0, sent: 0, skipped: 0, errors: 0 });
});

Deno.test('normalizePhone handles Kenyan formats', () => {
  assertEquals(normalizePhone('0712 345 678'), '+254712345678');
  assertEquals(normalizePhone('254112345678'), '+254112345678');
  assertEquals(normalizePhone('+254712345678'), '+254712345678');
  assertEquals(normalizePhone('12345'), null);
});
