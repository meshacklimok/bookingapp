# Payments, Tickets and QR

All payment logic runs in Supabase Edge Functions. Secrets never ship in the app.

## Booking and payment flow
1. Customer picks a slot or tier. `create-booking-hold` creates a `held` booking (10 min expiry).
2. Customer chooses M-Pesa or Paystack. `create-payment` creates a `payments` row (`pending`) and starts the provider flow.
3. The provider calls back. The function verifies it, marks the payment `success`, sets the booking `confirmed`, resolves and stores commission, and creates tickets.
4. The app listens to the booking row via Supabase Realtime and updates the screen. No polling.
5. If the hold expires or payment fails, the booking is cancelled and inventory is released.

## M-Pesa (Daraja STK Push)
- `create-payment` calls the STK Push API with the customer's phone (format `2547XXXXXXXX`), amount and account reference.
- Store `CheckoutRequestID` as the payment `reference`.
- `mpesa-callback` receives `ResultCode`. `0` means success, so store `MpesaReceiptNumber`. Any other code marks the payment `failed`.
- Callback endpoint must be public HTTPS. Validate that the `CheckoutRequestID` matches a pending payment and that the amount matches.
- Handle the case where the callback never arrives: a scheduled job queries the STK Push status for pending payments older than 2 minutes.

## Paystack
- `create-payment` initializes a transaction (amount in the smallest unit, currency KES) and returns the access code.
- The app opens the checkout (`flutter_paystack_plus` or a WebView).
- `paystack-webhook` verifies the `x-paystack-signature` header (HMAC SHA512 of the body with the secret key), then handles `charge.success`.
- Also call Paystack's verify endpoint before confirming, as a second check.

## Idempotency
The `reference` column on `payments` is unique. Webhooks and callbacks that arrive twice must not confirm a booking twice or create duplicate tickets. Confirm inside a transaction that checks the current status first.

## Commission and earnings
- On success, resolve the rate (service, then organization, then platform).
- Store on the booking: `commission_pct`, `commission_cents`, `org_earnings_cents = total_cents - commission_cents`.
- The dashboard's earnings screen (owners and admins only) reads `org_earnings_summary` and `org_earnings_rows`: gross, commission and net, per booking and in total, for a Nairobi calendar period. A booking counts once paid (commission snapshot set) and while `confirmed`, `completed` or `no_show`; cancelled ones are excluded.
- Organization earnings accumulate in a ledger. Payouts are manual or scheduled at first (M-Pesa B2C or bank transfer later).

## Cancellations and refunds
- Each service has a policy: full refund until `free_cancel_hours` before the start, `late_refund_pct` percent after that. If the organization cancels, the customer always gets everything back.
- `cancellation_quote` tells the app what a cancel would refund; `cancel_booking` does it. A booking cannot be cancelled once it started or a ticket was scanned.
- On cancel: tickets are voided, the booking records `refund_cents`, and `commission_cents` / `org_earnings_cents` shrink pro rata (the platform returns its share of the refund). A pending `refunds` row is created and both sides are notified.
- The money still goes back by hand for now: a platform admin sends it and marks the refund processed (`resolve_refund`), which sets the payment to `refunded` once it is fully refunded. The `process-refund` Edge Function sends Paystack refunds automatically: the app calls it right after a cancellation (customer, organization or admin), and admins can retry a pending one from the Refunds tab ("Send via Paystack"). It claims the refund (`processing`) so it cannot be sent twice, calls Paystack's refund API, and `paystack-webhook` settles it on `refund.processed` / `refund.failed` through `finish_refund`. A request error puts the refund back to `pending` with `last_error`. M-Pesa refunds stay manual: Daraja's reversal API cannot refund part of a payment.

## Payouts
- `org_balance`: payable = net earnings of settled bookings (over, or cancelled with money kept) minus payouts; upcoming earnings are shown separately because they can still be refunded.
- A platform admin sends the money (M-Pesa or bank) and records it with `record_payout`, which refuses more than the payable balance. Organizations read their balance and history; they cannot write payouts.

## Platform admin
The profile menu shows "Platform admin" for admins: approve or suspend organizations, resolve refunds, record payouts, and set commission (platform, organization or service) with `set_commission` / `clear_commission`.

## Notifications
- The database writes notifications (booking confirmed, new booking, cancelled, refund sent, payout sent, a reminder 24 hours before a booking). The app only reads them and marks them read; `data.route` is the in-app page opened on tap.
- `send_booking_reminders` runs every 15 minutes through pg_cron (`..._reminders_cron.sql`) and never sends the same reminder twice.
- Push delivery is not built: it would read the same rows and the `device_tokens` table from an Edge Function.

## Tickets and QR
- On confirmation, create one ticket per seat or person with a random `qr_token`.
- The QR payload is a random 256-bit token. It cannot be guessed or forged, because the server looks it up on every scan. A screenshot can be copied, but only the first scan is accepted.
- Planned for offline scanning (v1.5): HMAC-signed tokens so the scanner can validate without a connection.
- The app renders it with `qr_flutter`. Local caching so the wallet works offline is not built yet.

### Scanner (staff)
- `mobile_scanner` reads the QR and calls the `verify_ticket` database function.
- Server checks the token, ticket status and that the scanner belongs to the owning organization.
- It marks the ticket `used` atomically. A second scan returns "already used at HH:MM by NAME".
- Optional offline mode: download valid tokens for an event, scan locally, sync results later.

## Security checklist
- Verify every webhook and callback (signature, amount, reference).
- Rate limit booking and payment endpoints.
- Never trust amounts from the client. Compute totals server-side.
- Keep Daraja and Paystack keys only in Edge Function secrets.
- Log raw provider payloads in `payments.raw_payload` for dispute handling.
- Store only what is needed. Do not store card data.
