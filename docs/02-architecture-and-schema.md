# Architecture and Database Schema

## Stack
| Area | Choice |
|---|---|
| State management | Riverpod |
| Navigation | go_router (deep links) |
| Models | freezed + json_serializable |
| Backend | Supabase (Postgres, Auth, Realtime, Storage, Edge Functions, pg_cron) |
| Payments | M-Pesa Daraja, Paystack (via Edge Functions) |
| QR | `qr_flutter` (generate), `mobile_scanner` (scan) |
| Local storage | Hive or Isar (offline tickets and cache) |
| Push | Firebase Cloud Messaging |
| SMS | Africa's Talking |
| Monitoring | Sentry |

## Flutter project structure
```
lib/
  core/        theme, router, supabase client, errors, utils
  features/
    auth/
    discover/          search, categories, filters
    service_detail/
    booking/           slot / tier / date-range pickers
    checkout/          mpesa + paystack
    tickets/           wallet, QR view
    my_bookings/
    notifications/
    profile/
    org_dashboard/     services, calendar, staff, earnings
    scanner/           check-in
  shared/      widgets, models
```
Each feature has `data/` (repositories), `domain/` (models) and `presentation/` (screens, controllers).

## Core tables
```
profiles            id -> auth.users, full_name, phone, avatar_url
organizations       id, name, slug, logo, category, status, verified_at
org_members         org_id, user_id, role (owner|admin|staff)

services            id, org_id, title, description, booking_mode, price,
                    currency, duration_min, buffer_min, capacity, location,
                    images[], is_active
staff_services      staff_id, service_id
availability_rules  id, org_id, staff_id?, weekday, start_time, end_time
availability_exceptions  id, staff_id?, date, closed | custom hours

ticket_tiers        id, service_id, name, price, quantity, sold,
                    sales_start, sales_end

bookings            id, customer_id, service_id, staff_id?, tier_id?,
                    starts_at, ends_at, quantity,
                    status (held|pending_payment|confirmed|cancelled|completed|no_show),
                    expires_at, total_amount, promo_id?,
                    commission_pct, commission_amount, org_earnings
tickets             id, booking_id, qr_token, status (valid|used|void),
                    checked_in_at, checked_in_by
payments            id, booking_id, provider (mpesa|paystack), reference (unique),
                    amount, status, raw_payload jsonb
refunds             id, payment_id, amount, reason, status
```

## Commission
```
commission_settings  scope (platform|org|service), scope_id, pct
```
Resolution order: service, then organization, then platform default. On payment success the resolved rate is copied onto the booking (`commission_pct`, `commission_amount`, `org_earnings`). Later rate changes never affect past bookings.

## Later tables
```
payouts, wallet_transactions, vouchers, promo_codes
service_addons, packages, cancellation_policies
branches, favorites, follows, reviews, reports
recurrence_rules, waitlist_entries
notifications, device_tokens, audit_log
```

## Preventing double-booking
- **Appointments and resources:** Postgres exclusion constraint using `btree_gist` and `tstzrange` on (staff or resource, time range) for bookings in `held`, `pending_payment` or `confirmed`. Overlaps are impossible at the database level.
- **Events:** an atomic function runs `UPDATE ticket_tiers SET sold = sold + n WHERE id = $1 AND sold + n <= quantity` and fails if no row updates.
- **Holds:** a booking starts as `held` with `expires_at = now() + 10 minutes`. A `pg_cron` job cancels expired holds every minute and releases inventory.

## Row Level Security (summary)
| Table | Customer | Org member | Public |
|---|---|---|---|
| services | read active | manage own org | read active |
| bookings | own only | own org's | none |
| tickets | own only | own org's (scan) | none |
| payments | own only | own org's, read-only | none |
| organizations | read approved | edit own | read approved |

Payments, tickets and commission fields are written only by Edge Functions using the service role, never directly from the app.

## Edge Functions
| Function | Purpose |
|---|---|
| `create-payment` | Start M-Pesa STK push or Paystack transaction |
| `mpesa-callback` | Receive Daraja result, confirm booking |
| `paystack-webhook` | Verify signature, confirm booking |
| `process-refund` (v1.5) | Refund via provider, update ledger |
| `send-reminders` (v1.5) | Scheduled push and SMS reminders |

## Database functions (RPC)
| Function | Purpose |
|---|---|
| `get_available_slots` | Free appointment slots for a service on a date |
| `create_booking_hold` | Validate, price and hold a booking for 10 minutes |
| `cancel_booking` | Customer cancels an unpaid booking |
| `verify_ticket` | Staff scan: validates the QR token and marks it used atomically |
| `set_booking_outcome` | Staff mark completed or no-show |
| `confirm_booking_payment`, `mark_payment_failed` | Service role only, called by the payment functions |
| `release_expired_holds` | Run every minute by pg_cron |
