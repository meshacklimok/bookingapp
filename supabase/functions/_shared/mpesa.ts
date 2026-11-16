import { requireEnv } from './http.ts';

function baseUrl(): string {
  return Deno.env.get('MPESA_ENV') === 'production'
    ? 'https://api.safaricom.co.ke'
    : 'https://sandbox.safaricom.co.ke';
}

// Accepts 07XXXXXXXX, 01XXXXXXXX, +2547XXXXXXXX and 2547XXXXXXXX. Returns 2547XXXXXXXX or null.
export function normalizeKenyanPhone(input: string): string | null {
  const digits = input.replace(/[\s+-]/g, '');
  if (/^0[17]\d{8}$/.test(digits)) return `254${digits.slice(1)}`;
  if (/^254[17]\d{8}$/.test(digits)) return digits;
  return null;
}

async function accessToken(): Promise<string> {
  const credentials = btoa(`${requireEnv('MPESA_CONSUMER_KEY')}:${requireEnv('MPESA_CONSUMER_SECRET')}`);
  const res = await fetch(`${baseUrl()}/oauth/v1/generate?grant_type=client_credentials`, {
    headers: { Authorization: `Basic ${credentials}` },
  });
  if (!res.ok) throw new Error(`M-Pesa auth failed (${res.status})`);
  return (await res.json()).access_token;
}

// Daraja timestamps are yyyyMMddHHmmss in East Africa Time.
function timestamp(): string {
  return new Date(Date.now() + 3 * 3600 * 1000).toISOString().replace(/[-:T]/g, '').slice(0, 14);
}

function stkPassword(shortcode: string, ts: string): string {
  return btoa(`${shortcode}${requireEnv('MPESA_PASSKEY')}${ts}`);
}

export async function stkPush(params: {
  phone: string;
  amountKes: number;
  accountReference: string;
  description: string;
  callbackUrl: string;
}): Promise<{ checkoutRequestId: string; merchantRequestId: string }> {
  const shortcode = requireEnv('MPESA_SHORTCODE');
  const ts = timestamp();
  const password = stkPassword(shortcode, ts);

  const res = await fetch(`${baseUrl()}/mpesa/stkpush/v1/processrequest`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${await accessToken()}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      BusinessShortCode: shortcode,
      Password: password,
      Timestamp: ts,
      TransactionType: Deno.env.get('MPESA_TRANSACTION_TYPE') ?? 'CustomerPayBillOnline',
      Amount: params.amountKes,
      PartyA: params.phone,
      PartyB: Deno.env.get('MPESA_PARTY_B') ?? shortcode,
      PhoneNumber: params.phone,
      CallBackURL: params.callbackUrl,
      AccountReference: params.accountReference.slice(0, 12),
      TransactionDesc: params.description.slice(0, 13),
    }),
  });
  const body = await res.json();
  if (!res.ok || body.ResponseCode !== '0') {
    throw new Error(body.errorMessage ?? body.ResponseDescription ?? 'M-Pesa STK push failed');
  }
  return { checkoutRequestId: body.CheckoutRequestID, merchantRequestId: body.MerchantRequestID };
}

// Result codes Daraja uses while the customer has not answered the STK prompt yet.
const STILL_PROCESSING = new Set(['4999', '500.001.1001']);

export type StkStatus =
  | { state: 'processing' }
  | { state: 'done'; resultCode: string; raw: Record<string, unknown> };

// Asks Daraja how an STK push ended, for when its callback never arrived.
// The answer carries no receipt number or amount, only the result code.
export async function stkQuery(checkoutRequestId: string): Promise<StkStatus> {
  const shortcode = requireEnv('MPESA_SHORTCODE');
  const ts = timestamp();
  const res = await fetch(`${baseUrl()}/mpesa/stkpushquery/v1/query`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${await accessToken()}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      BusinessShortCode: shortcode,
      Password: stkPassword(shortcode, ts),
      Timestamp: ts,
      CheckoutRequestID: checkoutRequestId,
    }),
  });
  const body = await res.json();
  const code = String(body.ResultCode ?? body.errorCode ?? '');
  if (STILL_PROCESSING.has(code)) return { state: 'processing' };
  if (!res.ok || body.ResultCode === undefined) {
    throw new Error(body.errorMessage ?? `M-Pesa STK query failed (${res.status})`);
  }
  return { state: 'done', resultCode: code, raw: body };
}
