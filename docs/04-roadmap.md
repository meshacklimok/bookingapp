# Roadmap and Milestones

## Milestones
| # | Milestone | Deliverable |
|---|---|---|
| 1 | Foundation | Flutter project, Supabase project, auth, profiles, theme, routing |
| 2 | Schema and RLS | Migrations, seed data, hold and expiry logic, commission settings |
| 3 | Customer discovery | Service list, search, filters, service detail |
| 4 | Appointment booking | Staff availability, slot picker, hold, booking |
| 5 | Payments | M-Pesa STK Push, Paystack, callbacks, webhooks, idempotency |
| 6 | Tickets and QR | Ticket wallet, offline cache, staff scanner, check-in |
| 7 | Organization dashboard | Services, staff, schedules, bookings, earnings |
| 8 | Notifications and admin | Push, reminders, organization approval, commission controls |
| 9 | v1 hardening | Tests, Sentry, store assets, privacy policy, account deletion |
| 10 | v1.5 | Events and tiers, promo codes, deposits, cancellation, reviews, SMS |
| 11 | v2 | Resources, recurring and group bookings, wallet, analytics, waitlist |

## v1 definition of done
- A customer can sign up, find an appointment service, pay with M-Pesa or Paystack, and get a QR ticket.
- An organization can be approved, create services and staff, and see bookings and earnings.
- Double-booking is impossible, and expired holds are released automatically.
- Commission is calculated and stored per booking.
- Payment callbacks are idempotent and verified.
- Crash reporting is on, and core logic has automated tests.

## Open decisions
1. Commission default rate (platform level) and whether refunds reverse commission.
2. Payout method and schedule for organizations (manual, weekly M-Pesa B2C, bank).
3. Whether organizations can accept payment at the venue (cash), with commission billed later.
4. Cancellation and no-show defaults.
5. App name, branding and domain.

## Setup checklist
- [ ] Flutter SDK installed (`flutter doctor` clean)
- [ ] Supabase project created (URL and anon key)
- [ ] Safaricom Daraja sandbox account and credentials
- [ ] Paystack account (test keys)
- [ ] Firebase project (FCM only)
- [ ] Africa's Talking account (SMS, later)
- [ ] Sentry project
- [ ] Git repository initialised
