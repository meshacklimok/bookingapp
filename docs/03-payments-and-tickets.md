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
- Store on the booking: `commission_pct`, `commission_amount`, `org_earnings = total - commission`.
- Organization earnings accumulate in a ledger. Payouts are manual or scheduled at first (M-Pesa B2C or bank transfer later).

## Refunds
- Governed by the service's cancellation policy.
- `process-refund` calls the provider, writes a `refunds` row, voids tickets and adjusts the organization's ledger.
- Commission on refunded bookings is reversed in full or in part, according to your rule (decide before v1.5).

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
