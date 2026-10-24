-- Invariant tests for the booking schema. Each block raises on failure; "ok" notices show progress.
-- Runs as the superuser and switches to `authenticated` / `anon` to exercise RLS and function grants.

create function pg_temp.login(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  execute 'set role ' || case when p_uid is null then 'anon' else 'authenticated' end;
end $$;

create function pg_temp.logout() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', false);
end $$;

-- Runs sql and returns the error message, or null when it succeeded.
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlerrm;
end $$;

-- Runs a DML statement and returns the number of rows it affected.
create function pg_temp.rows(p_sql text) returns integer language plpgsql as $$
declare n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end $$;

create function pg_temp.check(p_name text, p_ok boolean, p_detail text default null) returns void
language plpgsql as $$
begin
  if p_ok is not true then
    raise exception 'FAIL: % %', p_name, coalesce('(' || p_detail || ')', '');
  end if;
  raise notice 'ok   %', p_name;
end $$;

-- Fixtures ---------------------------------------------------------------------------------------
insert into auth.users (id, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-000000000001', '{"full_name":"Alice"}'),   -- customer
  ('a0000000-0000-0000-0000-000000000002', '{"full_name":"Bob"}'),     -- other customer
  ('a0000000-0000-0000-0000-000000000003', '{"full_name":"Stella"}'),  -- staff / org owner
  ('a0000000-0000-0000-0000-000000000004', '{"full_name":"Mallory"}'), -- member of no org
  ('a0000000-0000-0000-0000-000000000005', '{"full_name":"Admin"}');   -- platform admin
update public.profiles set is_platform_admin = true where id = 'a0000000-0000-0000-0000-000000000005';

insert into public.organizations (id, name, slug, status, created_by)
values ('b0000000-0000-0000-0000-000000000001', 'Salon', 'salon', 'approved', 'a0000000-0000-0000-0000-000000000003');

insert into public.services (id, org_id, title, booking_mode, price_cents, duration_min, buffer_min) values
  ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'Haircut', 'appointment', 100000, 60, 0);
insert into public.services (id, org_id, title, booking_mode, price_cents, event_starts_at) values
  ('c0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'Meetup', 'event', 0, now() + interval '7 days');

insert into public.staff_services values ('a0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001');
insert into public.availability_rules (org_id, staff_id, weekday, start_time, end_time)
select 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003', d, '09:00', '12:00'
  from generate_series(0, 6) d;
insert into public.ticket_tiers (id, service_id, name, price_cents, quantity)
values ('d0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'Regular', 50000, 2);

select set_config('t.slot', (((now() at time zone 'Africa/Nairobi')::date + 2 + time '09:00') at time zone 'Africa/Nairobi')::text, false);

-- Setup sanity -----------------------------------------------------------------------------------
select pg_temp.check('sign-up trigger creates profiles',
  (select count(*) from public.profiles) = 5);
select pg_temp.check('creating an org makes the creator its owner',
  exists (select 1 from public.org_members where org_id = 'b0000000-0000-0000-0000-000000000001'
          and user_id = 'a0000000-0000-0000-0000-000000000003' and role = 'owner'));

-- Appointments: slots, holds, double-booking -----------------------------------------------------
select pg_temp.check('get_available_slots returns 09:00, 10:00, 11:00',
  (select count(*) from public.get_available_slots('c0000000-0000-0000-0000-000000000001',
     (current_setting('t.slot')::timestamptz at time zone 'Africa/Nairobi')::date)) = 3);

select pg_temp.login('a0000000-0000-0000-0000-000000000001');
select pg_temp.check('customer can hold a slot',
  (select status from public.create_booking_hold('c0000000-0000-0000-0000-000000000001',
     current_setting('t.slot')::timestamptz, 'a0000000-0000-0000-0000-000000000003')) = 'held');
select pg_temp.logout();

select pg_temp.check('held slot disappears from availability',
  (select count(*) from public.get_available_slots('c0000000-0000-0000-0000-000000000001',
     (current_setting('t.slot')::timestamptz at time zone 'Africa/Nairobi')::date)) = 2);

select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('second customer cannot take the same slot',
  pg_temp.err($$select public.create_booking_hold('c0000000-0000-0000-0000-000000000001',
     current_setting('t.slot')::timestamptz, 'a0000000-0000-0000-0000-000000000003')$$) = 'slot_unavailable');
select pg_temp.logout();

select pg_temp.check('exclusion constraint rejects an overlapping insert even when bypassing the function',
  pg_temp.err($$insert into public.bookings (customer_id, service_id, org_id, staff_id, starts_at, ends_at,
       status, total_cents, exclusive_key)
     values ('a0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001',
       'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003',
       current_setting('t.slot')::timestamptz + interval '30 minutes',
       current_setting('t.slot')::timestamptz + interval '90 minutes',
       'held', 0, 'a0000000-0000-0000-0000-000000000003')$$) like '%bookings_no_overlap%');

update public.bookings set status = 'cancelled';
select pg_temp.check('cancelled bookings no longer block the range',
  (select count(*) from public.get_available_slots('c0000000-0000-0000-0000-000000000001',
     (current_setting('t.slot')::timestamptz at time zone 'Africa/Nairobi')::date)) = 3);

-- Hold expiry ------------------------------------------------------------------------------------
select pg_temp.login('a0000000-0000-0000-0000-000000000001');
select public.create_booking_hold('c0000000-0000-0000-0000-000000000001',
  current_setting('t.slot')::timestamptz, 'a0000000-0000-0000-0000-000000000003');
select pg_temp.logout();

update public.bookings set expires_at = now() - interval '1 minute' where status = 'held';
select pg_temp.check('an expired hold frees the slot in get_available_slots before the cron runs',
  (select count(*) from public.get_available_slots('c0000000-0000-0000-0000-000000000001',
     (current_setting('t.slot')::timestamptz at time zone 'Africa/Nairobi')::date)) = 3);
select set_config('t.released', public.release_expired_holds()::text, false);
select pg_temp.check('release_expired_holds cancels expired holds',
  current_setting('t.released') = '1'
  and (select count(*) from public.bookings where status = 'held') = 0);

-- Events: inventory ------------------------------------------------------------------------------
select pg_temp.login('a0000000-0000-0000-0000-000000000001');
select public.create_booking_hold('c0000000-0000-0000-0000-000000000002', null, null,
  'd0000000-0000-0000-0000-000000000001', 2);
select pg_temp.logout();
select pg_temp.check('event hold reserves tier inventory',
  (select sold from public.ticket_tiers where id = 'd0000000-0000-0000-0000-000000000001') = 2);

select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('sold-out tier rejects further holds',
  pg_temp.err($$select public.create_booking_hold('c0000000-0000-0000-0000-000000000002', null, null,
     'd0000000-0000-0000-0000-000000000001', 1)$$) = 'sold_out');
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000001');
select public.cancel_booking((select id from public.bookings where tier_id is not null));
select pg_temp.logout();
select pg_temp.check('cancelling releases tier inventory',
  (select sold from public.ticket_tiers where id = 'd0000000-0000-0000-0000-000000000001') = 0);

-- Payments, commission, tickets ------------------------------------------------------------------
insert into public.commission_settings (scope, scope_id, pct) values
  ('org', 'b0000000-0000-0000-0000-000000000001', 15);
select pg_temp.check('commission resolves org over platform',
  public.resolve_commission_pct('c0000000-0000-0000-0000-000000000001') = 15);
insert into public.commission_settings (scope, scope_id, pct) values
  ('service', 'c0000000-0000-0000-0000-000000000001', 5);
select pg_temp.check('commission resolves service over org',
  public.resolve_commission_pct('c0000000-0000-0000-0000-000000000001') = 5);

select pg_temp.login('a0000000-0000-0000-0000-000000000001');
select public.create_booking_hold('c0000000-0000-0000-0000-000000000001',
  current_setting('t.slot')::timestamptz, 'a0000000-0000-0000-0000-000000000003');
select pg_temp.logout();

insert into public.payments (booking_id, customer_id, org_id, provider, reference, amount_cents)
select id, customer_id, org_id, 'mpesa', 'ws_CO_1', total_cents from public.bookings where status = 'held';

select public.confirm_booking_payment((select id from public.payments), 'RCPT1', '{}');
select public.confirm_booking_payment((select id from public.payments), 'RCPT1', '{}');
select pg_temp.check('payment confirms the booking and snapshots commission',
  (select status = 'confirmed' and commission_pct = 5 and commission_cents = 5000
          and org_earnings_cents = 95000 and expires_at is null from public.bookings
    where status <> 'cancelled'));
select pg_temp.check('confirming twice issues one ticket',
  (select count(*) from public.tickets) = 1);
update public.commission_settings set pct = 50 where scope = 'service';
select pg_temp.check('later rate changes do not touch past bookings',
  (select commission_pct from public.bookings where status = 'confirmed') = 5);

-- Late payment on a booking that was already cancelled
select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select public.create_booking_hold('c0000000-0000-0000-0000-000000000001',
  current_setting('t.slot')::timestamptz + interval '1 hour', 'a0000000-0000-0000-0000-000000000003');
select pg_temp.logout();
insert into public.payments (booking_id, customer_id, org_id, provider, reference, amount_cents)
select id, customer_id, org_id, 'paystack', 'late_1', total_cents from public.bookings where status = 'held';
update public.bookings set status = 'cancelled' where status = 'held';
select public.confirm_booking_payment((select id from public.payments where reference = 'late_1'));
select pg_temp.check('payment after cancellation is flagged for review and issues no ticket',
  (select needs_review from public.payments where reference = 'late_1')
  and (select count(*) from public.tickets) = 1);

-- Check-in ---------------------------------------------------------------------------------------
create temp table qr as select qr_token from public.tickets;
grant select on qr to public;

select pg_temp.login('a0000000-0000-0000-0000-000000000004');
select pg_temp.check('non-member cannot scan',
  (select public.verify_ticket((select qr_token from qr))->>'result') = 'forbidden');
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('org member scan succeeds once',
  (select public.verify_ticket((select qr_token from qr))->>'result') = 'ok');
select pg_temp.check('second scan reports already_used',
  (select public.verify_ticket((select qr_token from qr))->>'result') = 'already_used');
select pg_temp.check('unknown token is invalid',
  (select public.verify_ticket('nope')->>'result') = 'invalid');
select public.set_booking_outcome((select id from public.bookings where status = 'confirmed'), 'completed');
select pg_temp.logout();
select pg_temp.check('org member can mark a booking completed',
  exists (select 1 from public.bookings where status = 'completed'));

select pg_temp.login('a0000000-0000-0000-0000-000000000004');
select pg_temp.check('non-member cannot set a booking outcome',
  pg_temp.err($$select public.set_booking_outcome((select id from public.bookings limit 1), 'no_show')$$) is not null);
select pg_temp.logout();

-- RLS and grants ---------------------------------------------------------------------------------
select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('customer sees only their own bookings',
  (select count(*) from public.bookings where customer_id <> auth.uid()) = 0);
select pg_temp.check('customer cannot see other customers payments',
  (select count(*) from public.payments where customer_id <> auth.uid()) = 0);
select pg_temp.check('customer cannot see other customers tickets',
  (select count(*) from public.tickets) = 0);
select pg_temp.check('customer cannot insert bookings directly',
  pg_temp.err($$insert into public.bookings (customer_id, service_id, org_id, starts_at, ends_at, total_cents)
    values (auth.uid(), 'c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', now(),
            now() + interval '1 hour', 0)$$) is not null);
select pg_temp.check('customer cannot insert payments or tickets',
  pg_temp.err($$insert into public.tickets (booking_id, org_id, customer_id)
    select id, org_id, customer_id from public.bookings limit 1$$) is not null);
select pg_temp.check('customer cannot call confirm_booking_payment',
  pg_temp.err($$select public.confirm_booking_payment(gen_random_uuid())$$) like '%permission denied%');
select pg_temp.check('customer cannot call release_expired_holds',
  pg_temp.err($$select public.release_expired_holds()$$) like '%permission denied%');
select pg_temp.check('customer cannot grant themselves platform admin',
  pg_temp.err($$update public.profiles set is_platform_admin = true where id = auth.uid()$$) is not null
  or not (select is_platform_admin from public.profiles where id = auth.uid()));
select pg_temp.check('customer cannot edit commission settings',
  (select count(*) from public.commission_settings) = 0);
select pg_temp.check('customer cannot edit a service',
  pg_temp.rows('update public.services set price_cents = 0') = 0);
select pg_temp.check('customer cannot add themselves to an org',
  pg_temp.err($$insert into public.org_members values ('b0000000-0000-0000-0000-000000000001', auth.uid(), 'owner')$$) is not null);
select pg_temp.logout();

select pg_temp.login(null);
select pg_temp.check('anon cannot create holds',
  pg_temp.err($$select public.create_booking_hold('c0000000-0000-0000-0000-000000000001')$$) like '%permission denied%');
select pg_temp.check('anon can browse approved services',
  (select count(*) from public.services) = 2);
select pg_temp.check('anon cannot read bookings', pg_temp.err($$select * from public.bookings$$) like '%permission denied%'
  or (select count(*) from public.bookings) = 0);
select pg_temp.logout();

-- Organization lifecycle
select pg_temp.login('a0000000-0000-0000-0000-000000000004');
insert into public.organizations (name, slug, created_by) values ('Pending Co', 'pending-co', auth.uid());
select pg_temp.check('new orgs are pending and invisible to the public',
  (select status from public.organizations where slug = 'pending-co') = 'pending');
select pg_temp.check('org owner cannot self-approve',
  pg_temp.err($$update public.organizations set status = 'approved' where slug = 'pending-co'$$) like '%platform admins%');
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000005');
select pg_temp.check('platform admin can approve an org',
  pg_temp.err($$update public.organizations set status = 'approved' where slug = 'pending-co'$$) is null);
select pg_temp.logout();

-- Phase 2 additions: staff directory, org roles, storage
select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('customer can read a service''s staff names through get_service_staff',
  (select full_name from public.get_service_staff('c0000000-0000-0000-0000-000000000001')) = 'Stella');
select pg_temp.check('customer still cannot read the staff profile directly',
  (select count(*) from public.profiles where id = 'a0000000-0000-0000-0000-000000000003') = 0);
select pg_temp.logout();

insert into public.org_members values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'admin');
select pg_temp.login('a0000000-0000-0000-0000-000000000001');
select pg_temp.check('org admin can add staff',
  pg_temp.err($$insert into public.org_members values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', 'staff')$$) is null);
select pg_temp.check('org admin cannot add an owner',
  pg_temp.err($$insert into public.org_members values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000004', 'owner')$$) is not null);
select pg_temp.check('org admin cannot demote or remove the owner',
  pg_temp.rows($$delete from public.org_members where role = 'owner'$$) = 0
  and pg_temp.rows($$update public.org_members set role = 'staff' where role = 'owner'$$) = 0);
select pg_temp.check('org admin cannot promote themselves to owner',
  pg_temp.err($$update public.org_members set role = 'owner' where user_id = auth.uid()$$) is not null);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('org owner can add another owner',
  pg_temp.err($$insert into public.org_members values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000004', 'owner')$$) is null);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('user can upload to their own avatar folder',
  pg_temp.err($$insert into storage.objects (bucket_id, name) values ('avatars', auth.uid()::text || '/me.png')$$) is null);
select pg_temp.check('user cannot upload into someone else''s avatar folder',
  pg_temp.err($$insert into storage.objects (bucket_id, name) values ('avatars', 'a0000000-0000-0000-0000-000000000001/x.png')$$) is not null);
select pg_temp.check('staff-level member cannot upload organization images',
  pg_temp.err($$insert into storage.objects (bucket_id, name) values ('org-assets', 'b0000000-0000-0000-0000-000000000001/logo.png')$$) is not null);
select pg_temp.logout();
select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('org owner can upload organization images',
  pg_temp.err($$insert into storage.objects (bucket_id, name) values ('org-assets', 'b0000000-0000-0000-0000-000000000001/logo.png')$$) is null);
select pg_temp.logout();

-- Organization onboarding (milestone 7, slice 1)
insert into auth.users (id, raw_user_meta_data) values ('a0000000-0000-0000-0000-000000000006', '{"full_name":"Newcomer"}');

select pg_temp.login('a0000000-0000-0000-0000-000000000006');
select pg_temp.check('a new user can register an org and read it back in the same statement',
  pg_temp.err($$insert into public.organizations (name, slug, created_by) values ('Drafty', 'drafty', auth.uid()) returning id, status$$) is null);
select pg_temp.check('the registering user becomes its owner',
  (select role from public.org_members where org_id = (select id from public.organizations where slug = 'drafty')) = 'owner');
select pg_temp.check('a registered org is pending',
  (select status from public.organizations where slug = 'drafty') = 'pending');
select pg_temp.check('registering with a taken slug fails on the slug constraint',
  pg_temp.err($$insert into public.organizations (name, slug, created_by) values ('Drafty 2', 'drafty', auth.uid())$$) like '%organizations_slug_key%');
select pg_temp.check('a user cannot register an org on behalf of someone else',
  pg_temp.err($$insert into public.organizations (name, slug, created_by) values ('Fake', 'fake', 'a0000000-0000-0000-0000-000000000001')$$) is not null);
select pg_temp.check('a user cannot register an org that is already approved',
  pg_temp.err($$insert into public.organizations (name, slug, status, created_by) values ('Sneaky', 'sneaky', 'approved', auth.uid())$$) is not null);
select pg_temp.check('a user cannot register an org with no creator',
  pg_temp.err($$insert into public.organizations (name, slug) values ('Orphan', 'orphan')$$) is not null);
select pg_temp.check('owner of a pending org can draft a service',
  pg_temp.err($$insert into public.services (org_id, title, booking_mode, price_cents)
                values ((select id from public.organizations where slug = 'drafty'), 'Draft cut', 'appointment', 50000)$$) is null);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('other customers cannot see a pending org',
  (select count(*) from public.organizations where slug = 'drafty') = 0);
select pg_temp.check('other customers cannot see its draft service',
  (select count(*) from public.services where title = 'Draft cut') = 0);
select pg_temp.logout();

select pg_temp.login(null);
select pg_temp.check('anon cannot see a pending org or its draft service',
  (select count(*) from public.organizations where slug = 'drafty') = 0
  and (select count(*) from public.services where title = 'Draft cut') = 0);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000005');
update public.organizations set status = 'approved' where slug = 'drafty';
select pg_temp.logout();
select pg_temp.login(null);
select pg_temp.check('approving the org publishes its active services',
  (select count(*) from public.services where title = 'Draft cut') = 1);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000005');
update public.organizations set status = 'suspended' where slug = 'drafty';
select pg_temp.logout();
select pg_temp.login(null);
select pg_temp.check('suspending the org hides its services again',
  (select count(*) from public.services where title = 'Draft cut') = 0);
select pg_temp.logout();
select pg_temp.login('a0000000-0000-0000-0000-000000000006');
select pg_temp.check('a suspended org stays visible to its owner so the app can show the status',
  (select status from public.organizations where slug = 'drafty') = 'suspended');
select pg_temp.logout();

-- Service management (milestone 7, slice 2)
select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('org owner can create an event service',
  pg_temp.err($$insert into public.services (id, org_id, title, booking_mode, event_starts_at, event_ends_at)
                values ('c0000000-0000-0000-0000-0000000000e1', 'b0000000-0000-0000-0000-000000000001', 'Gala', 'event',
                        now() + interval '30 days', now() + interval '30 days 3 hours')$$) is null);
select pg_temp.check('an event cannot end before it starts',
  pg_temp.err($$insert into public.services (org_id, title, booking_mode, event_starts_at, event_ends_at)
                values ('b0000000-0000-0000-0000-000000000001', 'Backwards', 'event',
                        now() + interval '30 days', now() + interval '29 days')$$) like '%services_event_window_check%');
insert into public.ticket_tiers (service_id, name, price_cents, quantity) values
  ('c0000000-0000-0000-0000-0000000000e1', 'VIP', 500000, 10),
  ('c0000000-0000-0000-0000-0000000000e1', 'General', 150000, 100);
select pg_temp.check('an event''s price is its cheapest tier',
  (select price_cents from public.services where id = 'c0000000-0000-0000-0000-0000000000e1') = 150000);
update public.ticket_tiers set price_cents = 90000 where name = 'VIP';
select pg_temp.check('editing a tier price updates the event price',
  (select price_cents from public.services where id = 'c0000000-0000-0000-0000-0000000000e1') = 90000);
delete from public.ticket_tiers where name = 'VIP';
select pg_temp.check('deleting a tier updates the event price',
  (select price_cents from public.services where id = 'c0000000-0000-0000-0000-0000000000e1') = 150000);
delete from public.ticket_tiers where service_id = 'c0000000-0000-0000-0000-0000000000e1';
select pg_temp.check('an event with no tiers is priced at 0',
  (select price_cents from public.services where id = 'c0000000-0000-0000-0000-0000000000e1') = 0);
insert into public.ticket_tiers (service_id, name, price_cents, quantity) values
  ('c0000000-0000-0000-0000-0000000000e1', 'General', 150000, 100);
select pg_temp.check('a tier cannot be cut below the tickets already sold',
  pg_temp.err($$update public.ticket_tiers set sold = 5 where name = 'General'$$) is null
  and pg_temp.err($$update public.ticket_tiers set quantity = 3 where name = 'General'$$) is not null);
select pg_temp.check('appointment price is not touched by the tier sync',
  (select price_cents from public.services where id = 'c0000000-0000-0000-0000-000000000001') = 100000);
select pg_temp.check('org owner can deactivate a service',
  pg_temp.rows($$update public.services set is_active = false where id = 'c0000000-0000-0000-0000-0000000000e1'$$) = 1);
select pg_temp.logout();

select pg_temp.login(null);
select pg_temp.check('a deactivated service is hidden from the public',
  (select count(*) from public.services where id = 'c0000000-0000-0000-0000-0000000000e1') = 0);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('staff-level member cannot create a service',
  pg_temp.err($$insert into public.services (org_id, title) values ('b0000000-0000-0000-0000-000000000001', 'Nope')$$) is not null);
select pg_temp.check('staff-level member cannot edit tiers',
  pg_temp.rows($$update public.ticket_tiers set price_cents = 0$$) = 0);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000006');
select pg_temp.check('an owner of another org cannot create a service in this org',
  pg_temp.err($$insert into public.services (org_id, title) values ('b0000000-0000-0000-0000-000000000001', 'Hijack')$$) is not null);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('a service with bookings exists for the mode test',
  exists (select 1 from public.bookings where service_id = 'c0000000-0000-0000-0000-000000000001'));
select pg_temp.check('a service with bookings cannot switch booking mode',
  pg_temp.err($$update public.services set booking_mode = 'event' where id = 'c0000000-0000-0000-0000-000000000001'$$) like '%service_has_bookings%');
select pg_temp.check('a service without bookings can still switch booking mode',
  pg_temp.err($$update public.services set booking_mode = 'appointment' where id = 'c0000000-0000-0000-0000-0000000000e1'$$) is null);
select pg_temp.logout();

-- Staff and schedules (milestone 7, slice 3)
-- Ids: Stella 03 owner, Alice 01 admin, Bob 02 staff, Newcomer 06 owner of Drafty, Carol 07 has no org yet.
insert into auth.users (id, email, raw_user_meta_data) values ('a0000000-0000-0000-0000-000000000007', 'Carol@x.test', '{"full_name":"Carol"}');
update auth.users set email = 'stella@x.test' where id = 'a0000000-0000-0000-0000-000000000003';
select set_config('t.mon', (select min(d)::text from generate_series((now() at time zone 'Africa/Nairobi')::date + 7,
  (now() at time zone 'Africa/Nairobi')::date + 14, interval '1 day') d where extract(dow from d) = 1), false);
select set_config('t.tue', (current_setting('t.mon')::date + 1)::text, false);

select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('an owner can add staff by email, ignoring case and spaces',
  (select public.add_org_staff('b0000000-0000-0000-0000-000000000001', '  carol@X.TEST ')) = 'a0000000-0000-0000-0000-000000000007');
select pg_temp.check('the added person is a staff-level member',
  (select role from public.org_members where org_id = 'b0000000-0000-0000-0000-000000000001'
     and user_id = 'a0000000-0000-0000-0000-000000000007') = 'staff');
select pg_temp.check('adding the same person twice fails with already_member',
  pg_temp.err($$select public.add_org_staff('b0000000-0000-0000-0000-000000000001', 'carol@x.test')$$) like '%already_member%');
select pg_temp.check('an unknown email fails with user_not_found',
  pg_temp.err($$select public.add_org_staff('b0000000-0000-0000-0000-000000000001', 'nobody@x.test')$$) like '%user_not_found%');
select pg_temp.check('add_org_staff cannot create owners',
  pg_temp.err($$select public.add_org_staff('b0000000-0000-0000-0000-000000000001', 'stella@x.test', 'owner')$$) like '%forbidden%');
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('staff-level members cannot add staff',
  pg_temp.err($$select public.add_org_staff('b0000000-0000-0000-0000-000000000001', 'stella@x.test')$$) like '%forbidden%');
select pg_temp.logout();
select pg_temp.login('a0000000-0000-0000-0000-000000000006');
select pg_temp.check('an owner of another org cannot add staff here',
  pg_temp.err($$select public.add_org_staff('b0000000-0000-0000-0000-000000000001', 'stella@x.test')$$) like '%forbidden%');
select pg_temp.logout();
select pg_temp.login(null);
select pg_temp.check('anon cannot look up users by email',
  pg_temp.err($$select public.add_org_staff('b0000000-0000-0000-0000-000000000001', 'stella@x.test')$$) like '%permission denied%');
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('staff can be linked to a service of their org',
  pg_temp.err($$insert into public.staff_services values ('a0000000-0000-0000-0000-000000000007', 'c0000000-0000-0000-0000-000000000001')$$) is null);
select pg_temp.check('a non-member cannot be linked to a service',
  pg_temp.err($$insert into public.staff_services values ('a0000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-000000000001')$$) like '%not_org_member%');
select pg_temp.check('a non-member cannot be given weekly hours',
  pg_temp.err($$insert into public.availability_rules (org_id, staff_id, weekday, start_time, end_time)
                values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000006', 1, '09:00', '10:00')$$) like '%not_org_member%');
select pg_temp.check('a non-member cannot be given a day off',
  pg_temp.err($$insert into public.availability_exceptions (org_id, staff_id, date)
                values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000006', current_date)$$) like '%not_org_member%');
select public.set_staff_hours('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000007',
  '[{"weekday":1,"start_time":"09:00","end_time":"12:00"},{"weekday":1,"start_time":"13:00","end_time":"17:00"},
    {"weekday":2,"start_time":"09:00","end_time":"12:00"}]'::jsonb);
select pg_temp.check('set_staff_hours stores the whole week, with a gap between two windows on one day',
  (select count(*) from public.availability_rules where staff_id = 'a0000000-0000-0000-0000-000000000007') = 3
  and (select count(*) from public.availability_rules where staff_id = 'a0000000-0000-0000-0000-000000000007' and weekday = 1) = 2);
select pg_temp.check('overlapping windows on one day are rejected',
  pg_temp.err($$select public.set_staff_hours('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000007',
     '[{"weekday":1,"start_time":"09:00","end_time":"12:00"},{"weekday":1,"start_time":"11:00","end_time":"13:00"}]'::jsonb)$$)
  like '%availability_rules_no_overlap%');
select pg_temp.check('a rejected save leaves the previous hours untouched',
  (select count(*) from public.availability_rules where staff_id = 'a0000000-0000-0000-0000-000000000007') = 3);
select pg_temp.check('adjacent windows (touching at 12:00) are allowed',
  pg_temp.err($$select public.set_staff_hours('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000007',
     '[{"weekday":3,"start_time":"09:00","end_time":"12:00"},{"weekday":3,"start_time":"12:00","end_time":"15:00"}]'::jsonb)$$) is null);
select pg_temp.check('a window must end after it starts',
  pg_temp.err($$select public.set_staff_hours('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000007',
     '[{"weekday":1,"start_time":"12:00","end_time":"09:00"}]'::jsonb)$$) is not null);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('staff-level members cannot change anyone''s hours',
  pg_temp.err($$select public.set_staff_hours('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000007', '[]'::jsonb)$$) like '%forbidden%');
select pg_temp.logout();
select pg_temp.login(null);
select pg_temp.check('anon cannot call set_staff_hours',
  pg_temp.err($$select public.set_staff_hours('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000007', '[]'::jsonb)$$) like '%permission denied%');
select pg_temp.logout();

-- Two organizations, one person: each org's hours and days off are its own.
select pg_temp.login('a0000000-0000-0000-0000-000000000006');
select public.add_org_staff((select id from public.organizations where slug = 'drafty'), 'carol@x.test');
select public.set_staff_hours((select id from public.organizations where slug = 'drafty'), 'a0000000-0000-0000-0000-000000000007',
  (select jsonb_agg(jsonb_build_object('weekday', d, 'start_time', '08:00', 'end_time', '20:00')) from generate_series(0, 6) d));
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select public.set_staff_hours('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000007',
  '[{"weekday":1,"start_time":"09:00","end_time":"10:00"}]'::jsonb);
select pg_temp.logout();
select pg_temp.check('slots follow the service''s own org hours on a working day',
  (select count(*) from public.get_available_slots('c0000000-0000-0000-0000-000000000001', current_setting('t.mon')::date,
     'a0000000-0000-0000-0000-000000000007')) = 1);
select pg_temp.check('another org''s hours do not leak into this org''s slots',
  (select count(*) from public.get_available_slots('c0000000-0000-0000-0000-000000000001', current_setting('t.tue')::date,
     'a0000000-0000-0000-0000-000000000007')) = 0);

select pg_temp.login('a0000000-0000-0000-0000-000000000003');
insert into public.availability_exceptions (org_id, staff_id, date, is_closed)
values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000007', current_setting('t.mon')::date, true);
select pg_temp.check('the same date cannot have two exceptions in one org',
  pg_temp.err($$insert into public.availability_exceptions (org_id, staff_id, date, is_closed)
                values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000007', current_setting('t.mon')::date, true)$$)
  like '%availability_exceptions_org_staff_date_key%');
select pg_temp.logout();
select pg_temp.check('a day off removes that day''s slots',
  (select count(*) from public.get_available_slots('c0000000-0000-0000-0000-000000000001', current_setting('t.mon')::date,
     'a0000000-0000-0000-0000-000000000007')) = 0);
select pg_temp.login('a0000000-0000-0000-0000-000000000006');
select pg_temp.check('the other org can set its own exception on the same date',
  pg_temp.err($$insert into public.availability_exceptions (org_id, staff_id, date, is_closed)
                values ((select id from public.organizations where slug = 'drafty'), 'a0000000-0000-0000-0000-000000000007',
                        current_setting('t.mon')::date, true)$$) is null);
select pg_temp.logout();

-- Removing staff
insert into public.bookings (customer_id, service_id, org_id, staff_id, starts_at, ends_at, total_cents, status, exclusive_key)
values ('a0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000007', now() + interval '40 days', now() + interval '40 days 1 hour', 100000, 'confirmed',
        'a0000000-0000-0000-0000-000000000007');
select pg_temp.login('a0000000-0000-0000-0000-000000000001');
select pg_temp.check('staff with upcoming bookings cannot be removed',
  pg_temp.err($$delete from public.org_members where org_id = 'b0000000-0000-0000-0000-000000000001' and user_id = 'a0000000-0000-0000-0000-000000000007'$$)
  like '%staff_has_bookings%');
select pg_temp.logout();
update public.bookings set status = 'completed', starts_at = now() - interval '2 days', ends_at = now() - interval '2 days' + interval '1 hour'
 where staff_id = 'a0000000-0000-0000-0000-000000000007';
select pg_temp.login('a0000000-0000-0000-0000-000000000001');
select pg_temp.check('an admin can remove staff once their bookings are in the past',
  pg_temp.rows($$delete from public.org_members where org_id = 'b0000000-0000-0000-0000-000000000001' and user_id = 'a0000000-0000-0000-0000-000000000007'$$) = 1);
select pg_temp.logout();
select pg_temp.check('removing staff clears their links, hours and days off in that org only',
  (select count(*) from public.staff_services where staff_id = 'a0000000-0000-0000-0000-000000000007') = 0
  and (select count(*) from public.availability_rules where staff_id = 'a0000000-0000-0000-0000-000000000007'
         and org_id = 'b0000000-0000-0000-0000-000000000001') = 0
  and (select count(*) from public.availability_exceptions where staff_id = 'a0000000-0000-0000-0000-000000000007'
         and org_id = 'b0000000-0000-0000-0000-000000000001') = 0
  and (select count(*) from public.availability_rules where staff_id = 'a0000000-0000-0000-0000-000000000007') = 7);
select pg_temp.check('a removed staff member is no longer offered to customers',
  (select count(*) from public.get_service_staff('c0000000-0000-0000-0000-000000000001') where staff_id = 'a0000000-0000-0000-0000-000000000007') = 0);

-- Earnings ---------------------------------------------------------------------------------------
-- Fixtures sit in 2020 so they never mix with the now()-based bookings above. Org 2 checks nothing leaks across orgs.
insert into public.organizations (id, name, slug, status, created_by)
values ('b0000000-0000-0000-0000-000000000002', 'Other', 'other', 'approved', 'a0000000-0000-0000-0000-000000000005');
insert into public.services (id, org_id, title, booking_mode, price_cents, duration_min, buffer_min)
values ('c0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000002', 'Other cut', 'appointment', 33333, 60, 0);
insert into public.org_members (org_id, user_id, role)
values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000004', 'staff')
on conflict (org_id, user_id) do update set role = 'staff';

insert into public.bookings (customer_id, service_id, org_id, starts_at, ends_at, total_cents, status, commission_pct, commission_cents, org_earnings_cents, refund_cents)
select 'a0000000-0000-0000-0000-000000000002', v.svc, v.org, v.starts, v.starts + interval '1 hour', v.total, v.st::public.booking_status, v.pct, v.comm, v.net, v.refund
  from (values
    ('c0000000-0000-0000-0000-000000000001'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, timestamptz '2020-03-10 12:00+00', 100000, 'confirmed', 10.00, 10000, 90000, 0),
    -- 00:30 on 1 April in Nairobi, still 31 March in UTC
    ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', timestamptz '2020-03-31 21:30+00', 50000, 'completed', 10.00, 5000, 45000, 0),
    ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', timestamptz '2020-04-15 09:00+00', 20000, 'no_show', 20.00, 4000, 16000, 0),
    ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', timestamptz '2020-04-16 09:00+00', 99999, 'cancelled', 10.00, 0, 0, 99999),
    ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', timestamptz '2020-04-17 09:00+00', 77777, 'confirmed', null, null, null, 0),
    ('c0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000002', timestamptz '2020-03-10 12:00+00', 33333, 'confirmed', 10.00, 3333, 30000, 0),
    -- late cancellation, no refund: the organization keeps it
    ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', timestamptz '2021-05-05 09:00+00', 12000, 'cancelled', 10.00, 1200, 10800, 0)
  ) as v(svc, org, starts, total, st, pct, comm, net, refund);

select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('earnings summary adds up gross, commission and net; cancelled, unpaid and other-org bookings are left out',
  (select (booking_count, gross_cents, commission_cents, net_cents) = (3, 170000, 19000, 151000)
     from public.org_earnings_summary('b0000000-0000-0000-0000-000000000001', '2020-01-01', '2020-12-31')));
select pg_temp.check('a late cancellation with no refund still counts as earned; a fully refunded one does not',
  (select (booking_count, gross_cents, commission_cents, net_cents, refunded_cents) = (1, 12000, 1200, 10800, 0)
     from public.org_earnings_summary('b0000000-0000-0000-0000-000000000001', '2021-01-01', '2021-12-31')));
select pg_temp.check('net equals gross minus commission',
  (select gross_cents - commission_cents = net_cents from public.org_earnings_summary('b0000000-0000-0000-0000-000000000001', '2020-01-01', '2020-12-31')));
select pg_temp.check('dates are Nairobi dates: a 00:30 booking on 1 April counts in April, not March',
  (select (booking_count, gross_cents) = (1, 100000) from public.org_earnings_summary('b0000000-0000-0000-0000-000000000001', '2020-03-01', '2020-03-31'))
  and (select (booking_count, gross_cents) = (2, 70000) from public.org_earnings_summary('b0000000-0000-0000-0000-000000000001', '2020-04-01', '2020-04-30')));
select pg_temp.check('an empty period sums to zero, not null',
  (select (booking_count, gross_cents, commission_cents, net_cents) = (0, 0, 0, 0)
     from public.org_earnings_summary('b0000000-0000-0000-0000-000000000001', '1999-01-01', '1999-12-31')));
select pg_temp.check('per-booking rows carry the snapshot rate and come newest first',
  (select array_agg(commission_pct order by starts_at desc) = array[20.00, 10.00, 10.00]::numeric[]
     and array_agg(net_cents order by starts_at desc) = array[16000, 45000, 90000]::bigint[]
     from public.org_earnings_rows('b0000000-0000-0000-0000-000000000001', '2020-01-01', '2020-12-31')));
select pg_temp.check('rows respect the limit',
  (select count(*) from public.org_earnings_rows('b0000000-0000-0000-0000-000000000001', '2020-01-01', '2020-12-31', 2)) = 2);
select pg_temp.check('an owner of org 1 cannot read org 2 earnings',
  pg_temp.err($$select * from public.org_earnings_summary('b0000000-0000-0000-0000-000000000002')$$) like '%forbidden%');
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000001');
select pg_temp.check('an admin can read earnings',
  (select booking_count from public.org_earnings_summary('b0000000-0000-0000-0000-000000000001', '2020-01-01', '2020-12-31')) = 3);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000004');
select pg_temp.check('staff-level members cannot read earnings',
  pg_temp.err($$select * from public.org_earnings_summary('b0000000-0000-0000-0000-000000000001')$$) like '%forbidden%'
  and pg_temp.err($$select * from public.org_earnings_rows('b0000000-0000-0000-0000-000000000001')$$) like '%forbidden%');
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('customers cannot read earnings',
  pg_temp.err($$select * from public.org_earnings_summary('b0000000-0000-0000-0000-000000000001')$$) like '%forbidden%');
select pg_temp.logout();

select pg_temp.login(null);
select pg_temp.check('anonymous callers cannot call the earnings functions',
  pg_temp.err($$select * from public.org_earnings_summary('b0000000-0000-0000-0000-000000000001')$$) like '%permission denied%');
select pg_temp.logout();

-- Cancellation and refunds -----------------------------------------------------------------------
update public.services set free_cancel_hours = 24, late_refund_pct = 50 where id = 'c0000000-0000-0000-0000-000000000001';

-- one paid booking per case: id, start, total
create function pg_temp.paid_booking(p_id uuid, p_starts timestamptz, p_total bigint) returns void language plpgsql as $$
declare v_pay uuid := gen_random_uuid();
begin
  insert into public.bookings (id, customer_id, service_id, org_id, starts_at, ends_at, total_cents, status,
                               commission_pct, commission_cents, org_earnings_cents)
  values (p_id, 'a0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001',
          'b0000000-0000-0000-0000-000000000001', p_starts, p_starts + interval '1 hour', p_total, 'confirmed',
          10.00, p_total / 10, p_total - p_total / 10);
  insert into public.payments (id, booking_id, customer_id, org_id, provider, reference, amount_cents, status)
  values (v_pay, p_id, 'a0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'mpesa',
          'ref_' || p_id, p_total, 'success');
  insert into public.tickets (booking_id, org_id, customer_id)
  values (p_id, 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002');
end $$;

select pg_temp.paid_booking('e0000000-0000-0000-0000-000000000001', now() + interval '5 days', 100000);   -- early
select pg_temp.paid_booking('e0000000-0000-0000-0000-000000000002', now() + interval '2 hours', 100000);  -- late
select pg_temp.paid_booking('e0000000-0000-0000-0000-000000000003', now() + interval '3 hours', 100000);  -- org cancels
select pg_temp.paid_booking('e0000000-0000-0000-0000-000000000004', now() - interval '1 hour', 100000);   -- already started
select pg_temp.paid_booking('e0000000-0000-0000-0000-000000000005', now() + interval '3 days', 100000);   -- ticket used
update public.tickets set status = 'used' where booking_id = 'e0000000-0000-0000-0000-000000000005';

select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('the quote promises a full refund before the cutoff and the late percentage after it',
  (select refund_cents from public.cancellation_quote('e0000000-0000-0000-0000-000000000001')) = 100000
  and (select refund_cents from public.cancellation_quote('e0000000-0000-0000-0000-000000000002')) = 50000);
select pg_temp.check('a customer cancelling early is refunded in full',
  pg_temp.err($$select public.cancel_booking('e0000000-0000-0000-0000-000000000001', 'plans changed')$$) is null);
select pg_temp.check('a customer cancelling late is refunded the policy percentage',
  pg_temp.err($$select public.cancel_booking('e0000000-0000-0000-0000-000000000002')$$) is null);
select pg_temp.check('a started booking cannot be cancelled',
  pg_temp.err($$select public.cancel_booking('e0000000-0000-0000-0000-000000000004')$$) = 'cannot_cancel');
select pg_temp.check('a booking whose ticket was scanned cannot be cancelled',
  pg_temp.err($$select public.cancel_booking('e0000000-0000-0000-0000-000000000005')$$) = 'ticket_used');
select pg_temp.check('a cancelled booking cannot be cancelled twice',
  pg_temp.err($$select public.cancel_booking('e0000000-0000-0000-0000-000000000001')$$) = 'cannot_cancel');
select pg_temp.logout();

select pg_temp.check('early cancel: refund is the whole payment, commission reversed, tickets void',
  (select (status::text, refund_cents, commission_cents, org_earnings_cents, cancel_reason) = ('cancelled', 100000, 0, 0, 'plans changed')
     from public.bookings where id = 'e0000000-0000-0000-0000-000000000001')
  and (select status from public.tickets where booking_id = 'e0000000-0000-0000-0000-000000000001') = 'void');
select pg_temp.check('late cancel: half refunded, commission and net shrink pro rata',
  (select (refund_cents, commission_cents, org_earnings_cents) = (50000, 5000, 45000)
     from public.bookings where id = 'e0000000-0000-0000-0000-000000000002'));
select pg_temp.check('a pending refund row is created per refunded payment',
  (select array_agg(r.amount_cents order by r.amount_cents) = array[50000, 100000]::bigint[] and bool_and(r.status = 'pending')
     from public.refunds r join public.payments p on p.id = r.payment_id
    where p.booking_id in ('e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002')));
select pg_temp.check('the owner is told when a customer cancels',
  exists (select 1 from public.notifications where user_id = 'a0000000-0000-0000-0000-000000000003' and title = 'Booking cancelled'));

select pg_temp.login('a0000000-0000-0000-0000-000000000004');
select pg_temp.check('staff-level members and strangers cannot cancel a paid booking',
  pg_temp.err($$select public.cancel_booking('e0000000-0000-0000-0000-000000000003')$$) = 'cannot_cancel');
select pg_temp.logout();
select pg_temp.login('a0000000-0000-0000-0000-000000000005');
select pg_temp.check('a platform admin who is not a member cannot cancel a customer booking either',
  pg_temp.err($$select public.cancel_booking('e0000000-0000-0000-0000-000000000003')$$) = 'cannot_cancel');
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('an organization cancelling late still refunds the customer in full',
  (select refund_cents from public.cancellation_quote('e0000000-0000-0000-0000-000000000003')) = 100000
  and pg_temp.err($$select public.cancel_booking('e0000000-0000-0000-0000-000000000003', 'staff sick')$$) is null);
select pg_temp.check('the organization sees its refunds, with no other org involved',
  (select count(*) from public.refunds) >= 3);
select pg_temp.logout();
select pg_temp.check('the customer is told when the organization cancels',
  exists (select 1 from public.notifications where user_id = 'a0000000-0000-0000-0000-000000000002' and title like '%cancelled by the organizer%'));

select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('a customer sees only their own refunds',
  (select count(*) from public.refunds) = 3);
select pg_temp.check('a customer cannot resolve a refund',
  pg_temp.err($$select public.resolve_refund((select id from public.refunds limit 1), 'processed')$$) like '%forbidden%');
select pg_temp.logout();
select pg_temp.login('a0000000-0000-0000-0000-000000000004');
select pg_temp.check('a member of another role sees no refunds',
  (select count(*) from public.refunds) = 0);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000005');
select pg_temp.check('a platform admin processes a full refund and the payment becomes refunded',
  pg_temp.err($$select public.resolve_refund((select r.id from public.refunds r join public.payments p on p.id = r.payment_id
     where p.booking_id = 'e0000000-0000-0000-0000-000000000001'), 'processed', 'MPESA123')$$) is null);
select pg_temp.check('...and the payment is then marked refunded',
  (select status from public.payments where booking_id = 'e0000000-0000-0000-0000-000000000001') = 'refunded');
select pg_temp.check('a platform admin processes a partial refund',
  pg_temp.err($$select public.resolve_refund((select r.id from public.refunds r join public.payments p on p.id = r.payment_id
     where p.booking_id = 'e0000000-0000-0000-0000-000000000002'), 'processed')$$) is null);
select pg_temp.check('...a partial refund leaves the payment as success',
  (select status from public.payments where booking_id = 'e0000000-0000-0000-0000-000000000002') = 'success');
select pg_temp.check('a refund can only be resolved once',
  pg_temp.err($$select public.resolve_refund((select r.id from public.refunds r join public.payments p on p.id = r.payment_id
     where p.booking_id = 'e0000000-0000-0000-0000-000000000001'), 'failed')$$) = 'refund_not_pending');
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('earnings show the half-refunded booking net of the refund and omit fully refunded ones',
  (select (gross_cents, commission_cents, net_cents, refund_cents) = (50000, 5000, 45000, 50000)
     from public.org_earnings_rows('b0000000-0000-0000-0000-000000000001') where booking_id = 'e0000000-0000-0000-0000-000000000002')
  and not exists (select 1 from public.org_earnings_rows('b0000000-0000-0000-0000-000000000001')
                   where booking_id in ('e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000003')));
select pg_temp.logout();

-- unpaid holds keep working as before
select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select public.create_booking_hold('c0000000-0000-0000-0000-000000000001',
  current_setting('t.slot')::timestamptz, 'a0000000-0000-0000-0000-000000000003');
select pg_temp.logout();
select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('an organization cannot cancel a customer''s unpaid hold',
  pg_temp.err($$select public.cancel_booking((select id from public.bookings where status = 'held' and customer_id = 'a0000000-0000-0000-0000-000000000002'))$$) = 'cannot_cancel');
select pg_temp.logout();
select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('the customer can drop their own unpaid hold',
  pg_temp.err($$select public.cancel_booking((select id from public.bookings where status = 'held' and customer_id = 'a0000000-0000-0000-0000-000000000002'))$$) is null);
select pg_temp.logout();

-- Payouts ----------------------------------------------------------------------------------------
-- Org 2 has one settled 2020 booking (net 30000); add an upcoming one (net 9000) that is not payable yet.
insert into public.bookings (customer_id, service_id, org_id, starts_at, ends_at, total_cents, status, commission_pct, commission_cents, org_earnings_cents)
values ('a0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000002',
        now() + interval '3 days', now() + interval '3 days 1 hour', 10000, 'confirmed', 10.00, 1000, 9000);

select pg_temp.login('a0000000-0000-0000-0000-000000000005');
select pg_temp.check('balance splits payable (settled) from upcoming earnings',
  (select (payable_cents, upcoming_cents, paid_out_cents) = (30000, 9000, 0) from public.org_balance('b0000000-0000-0000-0000-000000000002')));
select pg_temp.check('a payout above the payable balance is refused, including the upcoming amount',
  pg_temp.err($$select public.record_payout('b0000000-0000-0000-0000-000000000002', 30001, 'mpesa')$$) = 'exceeds_balance'
  and pg_temp.err($$select public.record_payout('b0000000-0000-0000-0000-000000000002', 39000, 'mpesa')$$) = 'exceeds_balance');
select pg_temp.check('a zero or negative payout is refused',
  pg_temp.err($$select public.record_payout('b0000000-0000-0000-0000-000000000002', 0, 'mpesa')$$) = 'invalid_amount'
  and pg_temp.err($$select public.record_payout('b0000000-0000-0000-0000-000000000002', -5, 'mpesa')$$) = 'invalid_amount');
select pg_temp.check('an unknown payout method is refused by the table',
  pg_temp.err($$select public.record_payout('b0000000-0000-0000-0000-000000000002', 100, 'cheque')$$) like '%payouts_method_check%');
select pg_temp.check('a platform admin records a payout',
  pg_temp.err($$select public.record_payout('b0000000-0000-0000-0000-000000000002', 20000, 'mpesa', 'QWE123', 'October')$$) is null);
select pg_temp.check('the balance drops by what was paid',
  (select (payable_cents, upcoming_cents, paid_out_cents) = (10000, 9000, 20000) from public.org_balance('b0000000-0000-0000-0000-000000000002')));
select pg_temp.check('the same money cannot be paid twice',
  pg_temp.err($$select public.record_payout('b0000000-0000-0000-0000-000000000002', 10001, 'bank')$$) = 'exceeds_balance');
select pg_temp.check('the admin overview lists organizations with money in play',
  (select count(*) from public.admin_org_balances() where org_id = 'b0000000-0000-0000-0000-000000000002') = 1);
select pg_temp.logout();

select pg_temp.check('payout notifies the organization owners and admins',
  exists (select 1 from public.notifications where user_id = 'a0000000-0000-0000-0000-000000000005' and title = 'Payout sent'));

select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('an org owner can read their own balance but not record payouts or read another org''s',
  (select payable_cents > 0 from public.org_balance('b0000000-0000-0000-0000-000000000001'))
  and pg_temp.err($$select public.record_payout('b0000000-0000-0000-0000-000000000001', 100, 'mpesa')$$) like '%forbidden%'
  and pg_temp.err($$select * from public.org_balance('b0000000-0000-0000-0000-000000000002')$$) like '%forbidden%'
  and pg_temp.err($$select * from public.admin_org_balances()$$) like '%forbidden%');
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000005');
select public.record_payout('b0000000-0000-0000-0000-000000000001', 1000, 'bank', 'TX1');
select pg_temp.logout();
select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('an org sees its own payouts only',
  (select count(*) from public.payouts) = 1 and (select org_id from public.payouts) = 'b0000000-0000-0000-0000-000000000001');
select pg_temp.check('nobody writes payouts directly',
  pg_temp.err($$insert into public.payouts (org_id, amount_cents, method) values ('b0000000-0000-0000-0000-000000000001', 1, 'other')$$) is not null);
select pg_temp.logout();
select pg_temp.login('a0000000-0000-0000-0000-000000000004');
select pg_temp.check('staff-level members see no payouts and cannot read balances',
  (select count(*) from public.payouts) = 0
  and pg_temp.err($$select * from public.org_balance('b0000000-0000-0000-0000-000000000001')$$) like '%forbidden%');
select pg_temp.logout();
select pg_temp.login(null);
select pg_temp.check('anonymous callers cannot reach payout functions',
  pg_temp.err($$select public.record_payout('b0000000-0000-0000-0000-000000000001', 1, 'bank')$$) like '%permission denied%'
  and pg_temp.err($$select * from public.org_balance('b0000000-0000-0000-0000-000000000001')$$) like '%permission denied%');
select pg_temp.logout();

-- Commission controls ----------------------------------------------------------------------------
-- earlier tests left an org and a service override behind
delete from public.commission_settings where scope <> 'platform';
select pg_temp.login('a0000000-0000-0000-0000-000000000005');
select public.set_commission('platform', null, 12);
select pg_temp.check('the platform rate is used when nothing more specific exists',
  public.resolve_commission_pct('c0000000-0000-0000-0000-000000000001') = 12);
select public.set_commission('org', 'b0000000-0000-0000-0000-000000000001', 15);
select public.set_commission('service', 'c0000000-0000-0000-0000-000000000001', 5);
select pg_temp.check('the most specific rate wins: service, then org',
  public.resolve_commission_pct('c0000000-0000-0000-0000-000000000001') = 5
  and public.resolve_commission_pct('c0000000-0000-0000-0000-000000000002') = 15);
select public.set_commission('service', 'c0000000-0000-0000-0000-000000000001', 6);
select pg_temp.check('setting a rate twice updates instead of duplicating',
  (select count(*) from public.commission_settings where scope = 'service') = 1
  and public.resolve_commission_pct('c0000000-0000-0000-0000-000000000001') = 6);
select public.clear_commission('service', 'c0000000-0000-0000-0000-000000000001');
select public.clear_commission('org', 'b0000000-0000-0000-0000-000000000001');
select pg_temp.check('clearing overrides falls back to the platform rate',
  public.resolve_commission_pct('c0000000-0000-0000-0000-000000000001') = 12);
select pg_temp.check('bad commission input is refused',
  pg_temp.err($$select public.set_commission('platform', null, 101)$$) = 'invalid_pct'
  and pg_temp.err($$select public.set_commission('platform', null, -1)$$) = 'invalid_pct'
  and pg_temp.err($$select public.set_commission('org', null, 5)$$) = 'invalid_scope'
  and pg_temp.err($$select public.set_commission('platform', 'b0000000-0000-0000-0000-000000000001', 5)$$) = 'invalid_scope'
  and pg_temp.err($$select public.set_commission('org', gen_random_uuid(), 5)$$) = 'invalid_scope'
  and pg_temp.err($$select public.clear_commission('platform', null)$$) = 'invalid_scope');
select pg_temp.check('the admin list names each rate',
  (select name from public.admin_commissions() where scope = 'platform') = 'Platform default');
select public.set_commission('platform', null, 10);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000003');
select pg_temp.check('an org owner cannot change commission or list the rates',
  pg_temp.err($$select public.set_commission('org', 'b0000000-0000-0000-0000-000000000001', 0)$$) like '%forbidden%'
  and pg_temp.err($$select * from public.admin_commissions()$$) like '%forbidden%');
select pg_temp.logout();

-- Notifications ----------------------------------------------------------------------------------
delete from public.notifications;
select pg_temp.paid_booking('e0000000-0000-0000-0000-000000000010', now() + interval '5 hours', 100000);   -- reminder due
select pg_temp.paid_booking('e0000000-0000-0000-0000-000000000011', now() + interval '3 days', 100000);    -- too far away
select pg_temp.paid_booking('e0000000-0000-0000-0000-000000000012', now() - interval '1 hour', 100000);    -- already started
-- pg_temp.paid_booking inserts bookings as confirmed directly (an insert, not a status change), so no trigger fired yet.
select pg_temp.check('inserting a booking that is already confirmed sends no confirmation (only the status change does)',
  (select count(*) from public.notifications) = 0);

insert into public.bookings (id, customer_id, service_id, org_id, starts_at, ends_at, total_cents, status)
values ('e0000000-0000-0000-0000-000000000013', 'a0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001',
        'b0000000-0000-0000-0000-000000000001', now() + interval '9 days', now() + interval '9 days 1 hour', 100000, 'pending_payment');
update public.bookings set status = 'confirmed' where id = 'e0000000-0000-0000-0000-000000000013';
select pg_temp.check('confirming a booking notifies the customer and the organization owners and admins',
  (select count(*) from public.notifications where user_id = 'a0000000-0000-0000-0000-000000000002' and title = 'Booking confirmed') = 1
  and (select count(*) from public.notifications where user_id = 'a0000000-0000-0000-0000-000000000003' and title = 'New booking') = 1
  and (select count(*) from public.notifications where user_id = 'a0000000-0000-0000-0000-000000000004') = 0);
update public.bookings set status = 'completed' where id = 'e0000000-0000-0000-0000-000000000013';
update public.bookings set status = 'confirmed' where id = 'e0000000-0000-0000-0000-000000000013';
select pg_temp.check('a repeated confirmation does not duplicate notifications',
  (select count(*) from public.notifications where title = 'Booking confirmed') = 1);

select set_config('t.reminders', public.send_booking_reminders()::text, false);
select pg_temp.check('reminders go out only for confirmed bookings starting within 24 hours',
  current_setting('t.reminders') = '1'
  and (select array_agg(dedupe_key) from public.notifications where title = 'Coming up') = array['reminder:e0000000-0000-0000-0000-000000000010'],
  current_setting('t.reminders'));
select pg_temp.check('running reminders again sends nothing new',
  public.send_booking_reminders() = 0);
select pg_temp.check('a booking more than 24 hours away gets no reminder yet',
  (select count(*) from public.notifications where dedupe_key = 'reminder:e0000000-0000-0000-0000-000000000011') = 0);

select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('a user sees only their own notifications',
  (select count(*) from public.notifications) = 2 and (select bool_and(user_id = auth.uid()) from public.notifications));
select pg_temp.check('a user cannot edit the text of a notification',
  pg_temp.err($$update public.notifications set title = 'You won' $$) like '%permission denied%');
select pg_temp.check('a user can mark one notification read',
  pg_temp.rows($$update public.notifications set read_at = now() where title = 'Coming up'$$) = 1);
select pg_temp.check('mark_notifications_read marks the rest and reports how many',
  public.mark_notifications_read() = 1);
select pg_temp.check('...and nothing is left unread',
  (select count(*) from public.notifications where read_at is null) = 0 and public.mark_notifications_read() = 0);
select pg_temp.check('a user cannot create notifications',
  pg_temp.err($$insert into public.notifications (user_id, title) values (auth.uid(), 'x')$$) is not null);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000004');
select pg_temp.check('other users cannot mark someone else''s notifications read',
  public.mark_notifications_read() = 0
  and (select count(*) from public.notifications where user_id = 'a0000000-0000-0000-0000-000000000002' and read_at is null) = 0);
select pg_temp.check('other users do not see them either',
  (select count(*) from public.notifications) = 0);
select pg_temp.logout();

select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('reminders cannot be triggered by app users',
  pg_temp.err($$select public.send_booking_reminders()$$) like '%permission denied%');
select pg_temp.logout();

-- Automatic refunds -------------------------------------------------------------------------------
select pg_temp.login('a0000000-0000-0000-0000-000000000002');
select pg_temp.check('app users cannot call finish_refund directly',
  pg_temp.err($$select public.finish_refund((select id from public.refunds limit 1), 'processed')$$) like '%permission denied%');
select pg_temp.logout();

-- process-refund claims a refund by moving it to processing (service role)
update public.refunds set status = 'processing'
 where id = (select r.id from public.refunds r join public.payments p on p.id = r.payment_id
              where p.booking_id = 'e0000000-0000-0000-0000-000000000003');
select pg_temp.check('claiming a refund leaves exactly one in processing',
  (select count(*) from public.refunds where status = 'processing') = 1);

select pg_temp.login('a0000000-0000-0000-0000-000000000005');
select pg_temp.check('an admin can still settle a stuck processing refund',
  pg_temp.err($$select public.resolve_refund((select id from public.refunds where status = 'processing'), 'failed')$$) is null);
select pg_temp.logout();
select pg_temp.check('...and it is now failed with the error cleared',
  exists (select 1 from public.refunds r join public.payments p on p.id = r.payment_id
           where p.booking_id = 'e0000000-0000-0000-0000-000000000003' and r.status = 'failed' and r.last_error is null));

set role service_role;
select pg_temp.check('the service role cannot settle a refund twice',
  pg_temp.err($$select public.finish_refund((select r.id from public.refunds r join public.payments p on p.id = r.payment_id
     where p.booking_id = 'e0000000-0000-0000-0000-000000000003'), 'processed')$$) = 'refund_not_pending');
reset role;

\echo All invariant checks passed.
