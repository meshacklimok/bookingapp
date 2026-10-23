# Booking App: Overview and Features

## Vision
A multi-purpose booking platform built with **Flutter** and **Supabase**. Customers book appointments, event tickets and resources. Organizations list services and get paid. The platform takes a commission per booking.

## Decisions (confirmed)
| Topic | Decision |
|---|---|
| Frontend | Flutter (Dart), one app with role-aware navigation |
| Backend | Supabase (Postgres, Auth, Realtime, Storage, Edge Functions, pg_cron) |
| Payments | M-Pesa (Daraja STK Push) and Paystack |
| Currency | KES only (stored as integer cents; `currency` column kept for future) |
| Commission | Per booking, rate set by the owner. Configurable at platform, organization and service level (most specific wins). Snapshotted on each booking |
| Build order | Appointments first, then events, then resources |
| Languages | English and Swahili |

## Booking modes
| Mode | Examples | Availability logic |
|---|---|---|
| `appointment` | Salon, clinic, tutor, consultant | Slots from staff schedules, duration and buffer |
| `event` | Concerts, workshops, classes | Ticket tiers with capacity counts |
| `resource` | Venue, room, court, car | Date or time range, no overlaps |

The payment, ticket and QR pipeline is shared. Only the "pick a slot" step differs.

## Roles
- **Customer**: browse, book, pay, hold tickets, review.
- **Organization owner/admin**: services, staff, pricing, payouts, reports.
- **Staff**: own schedule, check-in and scanning.
- **Platform admin**: approve organizations, commission settings, disputes (Flutter Web).

A user can belong to several organizations.

## Features by release

### v1 (launchable)
- Auth: email, Google, phone OTP, guest browsing
- Discovery: categories, search, filters, service detail
- Appointment booking with staff selection and slot picker
- Inventory hold during checkout (10 min) with auto-expiry
- Payments: M-Pesa STK Push and Paystack
- Digital tickets with signed QR codes, offline wallet
- My bookings: upcoming, past, cancel
- Push notifications and reminders
- Organization dashboard basics: services, staff, schedules, bookings list
- Commission ledger and earnings view
- Admin approval of organizations

### v1.5
- Event ticketing with tiers and the QR scanner (check-in)
- Promo codes, deposits and partial payments
- Cancellation policies, reschedule
- Reviews and ratings (verified bookings only)
- SMS reminders (Africa's Talking)
- Receipts (PDF)

### v2
- Resource and venue booking
- Recurring and group bookings
- Wallet and vouchers
- Multi-branch organizations
- Analytics dashboards
- WhatsApp confirmations
- Waitlist
- Nearby search with map (PostGIS)
- Add to Apple/Google Wallet, ticket transfer, seat maps

## Customer features (full list)
Nearby search, open-now filter, favorites, follow organizations, reschedule in app, group payment links, gift vouchers, saved M-Pesa number, verified photo reviews, PDF receipts, Swahili and English, accessibility support.

## Organization features (full list)
Calendar (day, week, month, drag to reschedule), staff schedules and leave, per-staff services and pricing, deposits, cancellation policies, no-show tracking, add-ons and packages, promo codes, walk-in and manual bookings, customer list with notes and tags, analytics, payout dashboard with CSV export, waitlist, public business page with QR link, multi-branch.

## Platform admin features
Organization verification (KYC), suspend and approve, commission controls, disputes and refunds, revenue dashboard, featured listings and banners, category management, audit log, fraud checks.

## Trust and safety
Phone OTP verification, rate limiting on booking and payment endpoints, report and block, data export and account deletion (required by app stores).

## Non-functional requirements
- Offline: cached tickets and bookings, queued actions that sync later
- Observability: Sentry crash reporting, product analytics
- Testing: unit tests for booking and commission logic, integration tests for payment flows
- CI/CD: GitHub Actions for tests and builds
- Feature flags for gradual rollout
