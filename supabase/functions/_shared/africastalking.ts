import { requireEnv } from './http.ts';

// Africa's Talking wants international format without spaces (+2547...). Kenyan local numbers are converted.
export function normalizePhone(raw: string): string | null {
  const digits = raw.replace(/[\s()-]/g, '');
  if (/^\+\d{9,15}$/.test(digits)) return digits;
  if (/^254\d{9}$/.test(digits)) return `+${digits}`;
  if (/^0[17]\d{8}$/.test(digits)) return `+254${digits.slice(1)}`;
  return null;
}

// Sends one text. Throws when Africa's Talking rejects it, so the caller can count the failure.
export async function sendSms(to: string, message: string): Promise<void> {
  const username = requireEnv('AT_USERNAME');
  const host = username === 'sandbox' ? 'api.sandbox.africastalking.com' : 'api.africastalking.com';
  const form = new URLSearchParams({ username, to, message });
  const sender = Deno.env.get('AT_SENDER_ID');
  if (sender) form.set('from', sender);
  const res = await fetch(`https://${host}/version1/messaging`, {
    method: 'POST',
    headers: { apiKey: requireEnv('AT_API_KEY'), Accept: 'application/json', 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  });
  if (!res.ok) throw new Error(`Africa's Talking send failed (${res.status})`);
  const recipient = (await res.json())?.SMSMessageData?.Recipients?.[0];
  if (!recipient || recipient.statusCode >= 400) throw new Error(`Africa's Talking rejected the text (${recipient?.status})`);
}
