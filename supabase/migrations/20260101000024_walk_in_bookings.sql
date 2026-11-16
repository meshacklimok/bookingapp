-- Walk-in and manual bookings --------------------------------------------------------------------------------------------
-- A member of the organization books a customer who has no account (phone call, someone at the counter). The booking is
-- confirmed straight away and the money is taken at the venue, outside the platform. So these bookings carry no
-- commission snapshot (commission_cents stays null), which is what keeps them out of earnings and payouts: the
-- organization already has the money.

alter table public.bookings
  alter column customer_id drop not null,
  add column guest_name text check (guest_name is null or length(btrim(guest_name)) > 0),
  add column guest_phone text,
  add column venue_payment_method text check (venue_payment_method in ('cash', 'mpesa', 'card', 'unpaid', 'other')),
  add column created_by uuid references public.profiles (id) on delete set null,
  add constraint bookings_has_customer check (customer_id is not null or guest_name is not null);
alter table public.tickets alter column customer_id drop not null;

-- Everything that wrote to customer_id's user must now cope with a booking nobody can be notified about --------------

create or replace function public.send_booking_reminders() returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  insert into public.notifications (user_id, title, body, data, dedupe_key)
  select b.customer_id, 'Coming up',
         s.title || ' starts at ' || to_char(b.starts_at at time zone 'Africa/Nairobi', 'HH24:MI "on" Dy DD Mon') || '.',
         jsonb_build_object('booking_id', b.id, 'route', '/bookings'), 'reminder:' || b.id
    from public.bookings b
    join public.services s on s.id = b.service_id
   where b.status = 'confirmed' and b.customer_id is not null
     and b.starts_at > now() and b.starts_at <= now() + interval '24 hours'
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_booking_reminders() from public, anon, authenticated;

create or replace function public.cancellation_quote(p_booking_id uuid)
returns table (refund_cents bigint, full_refund boolean, by_org boolean)
language plpgsql stable security definer set search_path = public as $$
declare
  b public.bookings%rowtype;
  s public.services%rowtype;
  v_by_org boolean;
  v_refund bigint;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then
    raise exception 'cannot_cancel';
  end if;
  v_by_org := public.is_org_member(b.org_id, array['owner', 'admin']::public.org_role[]);
  if b.customer_id is distinct from auth.uid() and not v_by_org then
    raise exception 'cannot_cancel';
  end if;
  select * into s from public.services where id = b.service_id;
  v_refund := case when b.status = 'confirmed' and b.commission_cents is not null
                   then public.compute_refund(b.total_cents, b.starts_at, s.free_cancel_hours, s.late_refund_pct, v_by_org)
                   else 0 end;
  return query select v_refund, v_refund = b.total_cents, v_by_org;
end $$;

create or replace function public.cancel_booking(p_booking_id uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  b public.bookings%rowtype;
  s public.services%rowtype;
  v_by_org boolean;
  v_refund bigint;
  v_commission bigint;
  v_payment uuid;
  v_title text;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if not found or v_uid is null then
    raise exception 'cannot_cancel';
  end if;
  v_by_org := public.is_org_member(b.org_id, array['owner', 'admin']::public.org_role[]);
  if b.customer_id is distinct from v_uid and not v_by_org then
    raise exception 'cannot_cancel';
  end if;

  if b.status in ('held', 'pending_payment') then
    if b.customer_id is distinct from v_uid then
      raise exception 'cannot_cancel';
    end if;
    update public.bookings
       set status = 'cancelled', cancelled_at = now(), cancelled_by = v_uid
     where id = b.id;
    return;
  end if;

  if b.status <> 'confirmed' or b.starts_at <= now() then
    raise exception 'cannot_cancel';
  end if;
  if exists (select 1 from public.tickets t where t.booking_id = b.id and t.status = 'used') then
    raise exception 'ticket_used';
  end if;

  select * into s from public.services where id = b.service_id;
  -- walk-ins were paid at the venue (or not at all): nothing to refund through the platform
  v_refund := case when b.commission_cents is null then 0
                   else public.compute_refund(b.total_cents, b.starts_at, s.free_cancel_hours, s.late_refund_pct, v_by_org) end;
  v_commission := case when b.total_cents = 0 then 0
                       else round(coalesce(b.commission_cents, 0) * (b.total_cents - v_refund)::numeric / b.total_cents)::bigint end;

  update public.bookings
     set status = 'cancelled',
         cancelled_at = now(),
         cancelled_by = v_uid,
         cancel_reason = nullif(btrim(p_reason), ''),
         refund_cents = v_refund,
         commission_cents = case when b.commission_cents is null then null else v_commission end,
         org_earnings_cents = case when b.commission_cents is null then null else (b.total_cents - v_refund) - v_commission end
   where id = b.id;
  update public.tickets set status = 'void' where booking_id = b.id and status = 'valid';

  if v_refund > 0 then
    select id into v_payment from public.payments
     where booking_id = b.id and status = 'success' order by created_at desc limit 1;
    if v_payment is not null then
      insert into public.refunds (payment_id, amount_cents, reason)
      values (v_payment, v_refund, case when v_by_org and b.customer_id is distinct from v_uid then 'cancelled by organization' else 'cancelled by customer' end);
    end if;
  end if;

  select title into v_title from public.services where id = b.service_id;
  if v_by_org and b.customer_id is distinct from v_uid then
    if b.customer_id is not null then
      insert into public.notifications (user_id, title, body, data)
      values (b.customer_id, 'Booking cancelled by the organizer',
              v_title || ' was cancelled. You will be refunded in full.',
              jsonb_build_object('booking_id', b.id, 'route', '/bookings'));
    end if;
  else
    insert into public.notifications (user_id, title, body, data)
    select m.user_id, 'Booking cancelled', v_title || ' was cancelled by the customer.', jsonb_build_object('booking_id', b.id, 'route', '/org/' || b.org_id)
      from public.org_members m
     where m.org_id = b.org_id and m.role in ('owner', 'admin');
  end if;
end $$;
revoke execute on function public.cancel_booking(uuid, text) from public, anon;
grant execute on function public.cancel_booking(uuid, text) to authenticated;
revoke execute on function public.cancellation_quote(uuid) from public, anon;
grant execute on function public.cancellation_quote(uuid) to authenticated;

-- Creating one ------------------------------------------------------------------------------------------------------
-- Any member can book (front desk staff included). Opening hours are not enforced, since a walk-in may be right now or
-- after hours, but a staff member or resource still cannot be double-booked: the same exclusion constraint applies.
-- The price defaults to the list price; pass p_total_cents for a discount or a custom amount.
create function public.create_walk_in_booking(
  p_service_id uuid,
  p_guest_name text,
  p_guest_phone text default null,
  p_starts_at timestamptz default null,
  p_staff_id uuid default null,
  p_tier_id uuid default null,
  p_quantity integer default 1,
  p_total_cents bigint default null,
  p_payment_method text default 'cash',
  p_notes text default null
) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_service public.services%rowtype;
  v_tier public.ticket_tiers%rowtype;
  v_booking public.bookings%rowtype;
  v_qty integer := coalesce(p_quantity, 1);
  v_starts timestamptz;
  v_ends timestamptz;
  v_key uuid;
  v_staff uuid;
  v_total bigint;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_service from public.services where id = p_service_id and is_active;
  if not found then
    raise exception 'service_not_found';
  end if;
  if not public.is_org_member(v_service.org_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if exists (select 1 from public.organizations where id = v_service.org_id and status <> 'approved') then
    raise exception 'service_not_found';
  end if;
  if p_guest_name is null or length(btrim(p_guest_name)) = 0 then
    raise exception 'guest_name_required';
  end if;
  if v_qty < 1 or v_qty > 10 then
    raise exception 'invalid_quantity';
  end if;
  if p_total_cents is not null and p_total_cents < 0 then
    raise exception 'invalid_amount';
  end if;

  if v_service.booking_mode in ('appointment', 'resource') then
    if p_starts_at is null or p_starts_at < now() - interval '1 hour' then
      raise exception 'slot_required';
    end if;
    v_qty := 1;
    v_starts := p_starts_at;
    v_ends := p_starts_at + make_interval(mins => v_service.duration_min + v_service.buffer_min);
    v_total := v_service.price_cents;
    if v_service.booking_mode = 'appointment' then
      if p_staff_id is null or not exists (select 1 from public.staff_services where staff_id = p_staff_id and service_id = v_service.id) then
        raise exception 'staff_required';
      end if;
      v_key := p_staff_id;
      v_staff := p_staff_id;
    else
      v_key := v_service.id;
    end if;

  elsif v_service.booking_mode = 'event' then
    select * into v_tier from public.ticket_tiers where id = p_tier_id and service_id = v_service.id for update;
    if not found then
      raise exception 'tier_not_found';
    end if;
    if v_service.event_starts_at is null then
      raise exception 'event_date_missing';
    end if;
    update public.ticket_tiers set sold = sold + v_qty where id = v_tier.id and sold + v_qty <= quantity;
    if not found then
      raise exception 'sold_out';
    end if;
    v_starts := v_service.event_starts_at;
    v_ends := coalesce(v_service.event_ends_at, v_service.event_starts_at + interval '2 hours');
    v_total := v_tier.price_cents::bigint * v_qty;

  else
    raise exception 'mode_not_supported';
  end if;

  begin
    insert into public.bookings (
      customer_id, guest_name, guest_phone, venue_payment_method, created_by, service_id, org_id, staff_id, tier_id,
      starts_at, ends_at, quantity, status, total_cents, exclusive_key, notes
    ) values (
      null, btrim(p_guest_name), nullif(btrim(p_guest_phone), ''), coalesce(p_payment_method, 'cash'), v_uid,
      v_service.id, v_service.org_id, v_staff, p_tier_id,
      v_starts, v_ends, v_qty, 'confirmed', coalesce(p_total_cents, v_total), v_key, nullif(btrim(p_notes), '')
    ) returning * into v_booking;
  exception when exclusion_violation then
    raise exception 'slot_unavailable';
  end;

  insert into public.tickets (booking_id, org_id, customer_id)
  select v_booking.id, v_booking.org_id, null from generate_series(1, case when v_tier.id is not null then v_qty else 1 end);

  return v_booking;
end $$;
revoke execute on function public.create_walk_in_booking(uuid, text, text, timestamptz, uuid, uuid, integer, bigint, text, text) from public, anon;
grant execute on function public.create_walk_in_booking(uuid, text, text, timestamptz, uuid, uuid, integer, bigint, text, text) to authenticated;
