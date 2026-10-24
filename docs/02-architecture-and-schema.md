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
Money is stored as integer cents (KES). Times for availability are Africa/Nairobi.
```
profiles            id -> auth.users, full_name, phone, avatar_url, is_platform_admin
organizations       id, name, slug, description, logo_url, category,
                    status (pending|approved|suspended), created_by
org_members         org_id, user_id, role (owner|admin|staff)

services            id, org_id, title, description, category, booking_mode,
                    price_cents, currency, duration_min, buffer_min, capacity,
                    location, images[], event_starts_at, event_ends_at, is_active
staff_services      staff_id, service_id
availability_rules  id, org_id, staff_id, weekday (0 = Sunday), start_time, end_time
availability_exceptions  id, org_id, staff_id, date, is_closed, start_time?, end_time?

ticket_tiers        id, service_id, name, price_cents, quantity, sold,
                    sales_start, sales_end

bookings            id, customer_id, service_id, org_id, staff_id?, tier_id?,
                    starts_at, ends_at, quantity,
                    status (held|pending_payment|confirmed|cancelled|completed|no_show),
                    expires_at, total_cents,
                    commission_pct, commission_cents, org_earnings_cents,
                    exclusive_key, time_range (generated)
tickets             id, booking_id, org_id, customer_id, qr_token, status (valid|used|void),
                    checked_in_at, checked_in_by
payments            id, booking_id, customer_id, org_id, provider (mpesa|paystack),
                    reference (unique), amount_cents, phone, status, provider_receipt,
                    raw_payload jsonb, needs_review
refunds             id, payment_id, amount_cents, reason, status
device_tokens, notifications
```

## Commission
```
commission_settings  scope (platform|org|service), scope_id, pct
```
Resolution order: service, then organization, then platform default. On payment success the resolved rate is copied onto the booking (`commission_pct`, `commission_cents`, `org_earnings_cents`). Later rate changes never affect past bookings.

## Later tables
```
payouts, wallet_transactions, vouchers, promo_codes
service_addons, packages, cancellation_policies
branches, favorites, follows, reviews, reports
recurrence_rules, waitlist_entries
notifications, device_tokens, audit_log
```

## Preventing double-booking
- **Appointments and resources:** Postgres exclusion constraint using `btree_gist` and `tstzrange` on `bookings.exclusive_key` (staff id for appointments, service id for resources) and `time_range` for bookings in `held`, `pending_payment` or `confirmed`. Overlaps are impossible at the database level.
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

Organization admins cannot create, change or remove owners. Storage buckets: `avatars` (folder per user id) and `org-assets` (folder per organization id, owners and admins write).

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
| `get_service_staff` | Public name and avatar of a service's staff, for the slot picker |
| `create_booking_hold` | Validate, price and hold a booking for 10 minutes |
| `cancel_booking` | Customer cancels an unpaid booking |
| `verify_ticket` | Staff scan: validates the QR token and marks it used atomically |
| `set_booking_outcome` | Staff mark completed or no-show |
| `confirm_booking_payment`, `mark_payment_failed` | Service role only, called by the payment functions |
| `release_expired_holds` | Run every minute by pg_cron |
