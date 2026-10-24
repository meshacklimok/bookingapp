import { requireEnv } from './http.ts';

export type PaystackRefund = { status: string; id: string | null };

// Asks Paystack to refund `amountCents` of a transaction. Paystack refunds are asynchronous: `status` is usually
// `pending` or `processing` and the final result arrives in the refund.* webhooks.
export async function createPaystackRefund(params: {
  transactionReference: string;
  amountCents: number;
  note: string;
}): Promise<PaystackRefund> {
  const res = await fetch('https://api.paystack.co/refund', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${requireEnv('PAYSTACK_SECRET_KEY')}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      transaction: params.transactionReference,
      amount: params.amountCents,
      currency: 'KES',
      merchant_note: params.note.slice(0, 200),
    }),
  });
  const body = await res.json();
  if (!res.ok || !body.status) throw new Error(body.message ?? `Paystack refund failed (${res.status})`);
  return { status: String(body.data?.status ?? 'pending'), id: body.data?.id != null ? String(body.data.id) : null };
}
