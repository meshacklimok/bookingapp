-- Demo data for local development: one approved organization with an event and two ticket tiers.
-- Appointment services need staff linked to real auth users; see supabase/README.md.

insert into public.organizations (id, name, slug, description, category, status)
values ('11111111-1111-1111-1111-111111111111', 'Demo Events Ltd', 'demo-events',
        'Sample organization for testing the booking flow.', 'Events', 'approved');

insert into public.services (id, org_id, title, description, category, booking_mode, price_cents,
                             duration_min, location, event_starts_at, event_ends_at)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111',
        'Nairobi Tech Meetup', 'An evening of talks and networking.', 'Events', 'event', 50000,
        120, 'iHub, Nairobi', now() + interval '14 days', now() + interval '14 days 3 hours');

insert into public.ticket_tiers (service_id, name, price_cents, quantity)
values ('22222222-2222-2222-2222-222222222222', 'Regular', 50000, 100),
       ('22222222-2222-2222-2222-222222222222', 'VIP', 150000, 20);
