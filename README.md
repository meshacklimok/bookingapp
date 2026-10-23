# Booking App (working title)

A mobile app, built with Flutter and Supabase, that lets people in Kenya **book anything in one place** and pay with **M-Pesa or card**. Businesses use the same app to list their services, take bookings and get paid.

## What it is
One platform for three kinds of bookings:
- **Appointments**: salons, barbers, clinics, tutors, consultants, mechanics.
- **Events**: concerts, workshops, classes, with tickets.
- **Resources**: venues, rooms, sports courts, vehicles.

Customers search, pick a time or ticket, pay, and receive a **QR code ticket** stored on their phone. Businesses check customers in by scanning that QR code.

## The problem
- Small businesses take bookings through calls, WhatsApp and paper notebooks. This causes double-bookings, no-shows and lost customers.
- Customers can't see real availability, so they message back and forth to find a slot.
- Event organizers lack simple ticketing with M-Pesa and have trouble stopping fake or duplicated tickets.
- Existing booking tools are built for other markets and don't treat M-Pesa as a first-class payment method.

## The solution
- **Real-time availability:** the system makes double-booking impossible.
- **M-Pesa STK Push and Paystack** payments built in, with deposits so no-shows cost less.
- **Signed QR tickets:** they can't be forged, and they work offline.
- **Automatic reminders** by push and SMS, which reduce no-shows.
- **A business dashboard:** calendar, staff schedules, earnings and payouts.

## Who it is for
| User | What they get |
|---|---|
| **Customers** | Find and book services nearby, pay with M-Pesa, keep tickets in one wallet, get reminders |
| **Businesses (organizations)** | Online booking page, calendar, staff management, payments, customer list, earnings reports |
| **Staff** | Personal schedule and a QR scanner for check-in |
| **Platform owner** | Approves businesses and earns a commission on each booking, at a rate you set |

## How it makes money
A commission is taken **per booking**. The rate is set by the platform owner and can differ per organization or per service. The rate is recorded on each booking when it is paid, so later changes never affect past records.

## Scope
- **Market:** Kenya, KES only, English and Swahili.
- **Platforms:** Android and iOS (Flutter), plus a web admin panel later.
- **Release plan:** v1 appointments, v1.5 events and scanner, v2 resources and extras.

## Documentation
| File | Contents |
|---|---|
| [docs/01-overview-and-features.md](docs/01-overview-and-features.md) | Decisions, roles, features by release |
| [docs/02-architecture-and-schema.md](docs/02-architecture-and-schema.md) | Stack, project structure, database, security |
| [docs/03-payments-and-tickets.md](docs/03-payments-and-tickets.md) | M-Pesa, Paystack, commission, QR tickets |
| [docs/04-roadmap.md](docs/04-roadmap.md) | Milestones, definition of done, open decisions |
