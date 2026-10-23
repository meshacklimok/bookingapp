-- Business logic: access helpers, availability, holds, payment confirmation, ticket check-in.

create function public.is_platform_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_platform_admin from public.profiles where id = auth.uid()), false)
$$;

create function public.is_org_member(p_org_id uuid, p_roles public.org_role[] default null) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.org_members
    where org_id = p_org_id
      and user_id = auth.uid()
      and (p_roles is null or role = any (p_roles))
  )
$$;

-- Most specific commission wins: service, then organization, then platform default.
create function public.resolve_commission_pct(p_service_id uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select pct from public.commission_settings where scope = 'service' and scope_id = p_service_id),
    (select cs.pct from public.commission_settings cs
       join public.services s on s.org_id = cs.scope_id
      where cs.scope = 'org' and s.id = p_service_id),
    (select pct from public.commission_settings where scope = 'platform'),
    0
  )
$$;

create function public.release_expired_holds() returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  update public.bookings
     set status = 'cancelled'
   where status in ('held', 'pending_payment') and expires_at < now();
  get diagnostics n = row_count;
  return n;
end $$;

-- Free slots for one appointment service on one local (Africa/Nairobi) date.
create function public.get_available_slots(p_service_id uuid, p_date date, p_staff_id uuid default null)
returns table (staff_id uuid, slot_start timestamptz, slot_end timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  v_service public.services%rowtype;
  v_tz constant text := 'Africa/Nairobi';
  v_step interval;
  v_duration interval;
begin
  select s.* into v_service
    from public.services s
    join public.organizations o on o.id = s.org_id
   where s.id = p_service_id and s.is_active and s.booking_mode = 'appointment' and o.status = 'approved';
  if not found then
    return;
  end if;

  v_duration := make_interval(mins => v_service.duration_min);
  v_step := make_interval(mins => v_service.duration_min + v_service.buffer_min);

  return query
  with staff as (
    select ss.staff_id as sid
      from public.staff_services ss
     where ss.service_id = p_service_id
       and (p_staff_id is null or ss.staff_id = p_staff_id)
  ),
  windows as (
    select st.sid,
           (p_date + r.start_time) at time zone v_tz as w_start,
           (p_date + r.end_time) at time zone v_tz as w_end
      from staff st
      join public.availability_rules r
        on r.staff_id = st.sid and r.weekday = extract(dow from p_date)::smallint
     where not exists (
       select 1 from public.availability_exceptions e where e.staff_id = st.sid and e.date = p_date
     )
    union all
    select st.sid,
           (p_date + e.start_time) at time zone v_tz,
           (p_date + e.end_time) at time zone v_tz
      from staff st
      join public.availability_exceptions e on e.staff_id = st.sid and e.date = p_date
     where not e.is_closed
  ),
  candidates as (
    select w.sid, g as s_start
      from windows w,
           generate_series(w.w_start, w.w_end - v_duration, v_step) g
  )
  select c.sid, c.s_start, c.s_start + v_duration
    from candidates c
   where c.s_start >= now()
     and not exists (
       select 1 from public.bookings b
        where b.exclusive_key = c.sid
          and b.status in ('held', 'pending_payment', 'confirmed')
          and (b.status = 'confirmed' or b.expires_at > now())
          and b.time_range && tstzrange(c.s_start, c.s_start + v_step, '[)')
     )
   order by c.s_start, c.sid;
end $$;

-- Creates a 10 minute hold for the signed-in user. Prices are computed here, never trusted from the client.
create function public.create_booking_hold(
  p_service_id uuid,
  p_starts_at timestamptz default null,
  p_staff_id uuid default null,
  p_tier_id uuid default null,
  p_quantity integer default 1
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
  v_total bigint;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_qty < 1 or v_qty > 10 then
    raise exception 'invalid_quantity';
  end if;

  select s.* into v_service
    from public.services s
    join public.organizations o on o.id = s.org_id
   where s.id = p_service_id and s.is_active and o.status = 'approved';
  if not found then
    raise exception 'service_not_found';
  end if;

  perform public.release_expired_holds();

  if v_service.booking_mode = 'appointment' then
    if p_starts_at is null or p_staff_id is null then
      raise exception 'slot_required';
    end if;
    if not exists (
      select 1
        from public.get_available_slots(p_service_id, (p_starts_at at time zone 'Africa/Nairobi')::date, p_staff_id) g
       where g.slot_start = p_starts_at
    ) then
      raise exception 'slot_unavailable';
    end if;
    v_qty := 1;
    v_starts := p_starts_at;
    v_ends := p_starts_at + make_interval(mins => v_service.duration_min + v_service.buffer_min);
    v_key := p_staff_id;
    v_total := v_service.price_cents;

  elsif v_service.booking_mode = 'event' then
    select * into v_tier from public.ticket_tiers where id = p_tier_id and service_id = p_service_id for update;
    if not found then
      raise exception 'tier_not_found';
    end if;
    if (v_tier.sales_start is not null and now() < v_tier.sales_start)
       or (v_tier.sales_end is not null and now() > v_tier.sales_end) then
      raise exception 'sales_closed';
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
      customer_id, service_id, org_id, staff_id, tier_id, starts_at, ends_at,
      quantity, status, expires_at, total_cents, exclusive_key
    ) values (
      v_uid, v_service.id, v_service.org_id, p_staff_id, p_tier_id, v_starts, v_ends,
      v_qty, 'held', now() + interval '10 minutes', v_total, v_key
    ) returning * into v_booking;
  exception when exclusion_violation then
    raise exception 'slot_unavailable';
  end;

  return v_booking;
end $$;

-- Customers can drop a booking that is not paid yet. Refunds for paid bookings come with cancellation policies.
create function public.cancel_booking(p_booking_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.bookings
     set status = 'cancelled'
   where id = p_booking_id
     and customer_id = auth.uid()
     and status in ('held', 'pending_payment');
  if not found then
    raise exception 'cannot_cancel';
  end if;
end $$;

-- Organization staff mark a confirmed booking as completed or no-show.
create function public.set_booking_outcome(p_booking_id uuid, p_status public.booking_status) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
begin
  if p_status not in ('completed', 'no_show') then
    raise exception 'invalid_status';
  end if;
  select org_id into v_org from public.bookings where id = p_booking_id;
  if v_org is null or not public.is_org_member(v_org) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update public.bookings set status = p_status where id = p_booking_id and status = 'confirmed';
  if not found then
    raise exception 'booking_not_confirmed';
  end if;
end $$;

-- Called only by Edge Functions (service role) after the provider confirms money was received.
-- Idempotent: a repeated callback for the same payment does nothing.
create function public.confirm_booking_payment(
  p_payment_id uuid,
  p_receipt text default null,
  p_raw jsonb default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_pay public.payments%rowtype;
  v_booking public.bookings%rowtype;
  v_pct numeric;
  v_commission bigint;
  v_count integer;
begin
  select * into v_pay from public.payments where id = p_payment_id for update;
  if not found then
    raise exception 'payment_not_found';
  end if;
  if v_pay.status = 'success' then
    return;
  end if;

  update public.payments
     set status = 'success',
         provider_receipt = p_receipt,
         raw_payload = coalesce(p_raw, raw_payload),
         updated_at = now()
   where id = p_payment_id;

  select * into v_booking from public.bookings where id = v_pay.booking_id for update;
  if v_booking.status not in ('held', 'pending_payment') then
    update public.payments set needs_review = true where id = p_payment_id;
    return;
  end if;

  v_pct := public.resolve_commission_pct(v_booking.service_id);
  v_commission := round(v_booking.total_cents * v_pct / 100);

  update public.bookings
     set status = 'confirmed',
         expires_at = null,
         commission_pct = v_pct,
         commission_cents = v_commission,
         org_earnings_cents = total_cents - v_commission
   where id = v_booking.id;

  v_count := case when v_booking.tier_id is not null then v_booking.quantity else 1 end;
  insert into public.tickets (booking_id, org_id, customer_id)
  select v_booking.id, v_booking.org_id, v_booking.customer_id from generate_series(1, v_count);
end $$;

-- Called only by Edge Functions when the provider reports a failed or cancelled payment.
create function public.mark_payment_failed(p_payment_id uuid, p_raw jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.payments
     set status = 'failed', raw_payload = coalesce(p_raw, raw_payload), updated_at = now()
   where id = p_payment_id and status = 'pending';
  -- let the customer retry within the original hold window
  update public.bookings
     set status = 'held'
   where id = (select booking_id from public.payments where id = p_payment_id)
     and status = 'pending_payment';
end $$;

-- Staff scan a QR code. The ticket is marked used atomically, so a second scan is rejected.
create function public.verify_ticket(p_qr_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_ticket public.tickets%rowtype;
  v_title text;
  v_holder text;
  v_starts timestamptz;
begin
  select * into v_ticket from public.tickets where qr_token = p_qr_token;
  if not found then
    return jsonb_build_object('result', 'invalid');
  end if;
  if auth.uid() is null or not public.is_org_member(v_ticket.org_id) then
    return jsonb_build_object('result', 'forbidden');
  end if;

  select s.title, b.starts_at, p.full_name
    into v_title, v_starts, v_holder
    from public.bookings b
    join public.services s on s.id = b.service_id
    join public.profiles p on p.id = b.customer_id
   where b.id = v_ticket.booking_id;

  update public.tickets
     set status = 'used', checked_in_at = now(), checked_in_by = auth.uid()
   where id = v_ticket.id and status = 'valid';

  if found then
    return jsonb_build_object('result', 'ok', 'service', v_title, 'holder', v_holder, 'starts_at', v_starts);
  end if;

  select * into v_ticket from public.tickets where id = v_ticket.id;
  return jsonb_build_object(
    'result', case when v_ticket.status = 'used' then 'already_used' else 'void' end,
    'service', v_title,
    'checked_in_at', v_ticket.checked_in_at
  );
end $$;

-- Execution rights: functions are public by default, so lock down the sensitive ones.
revoke execute on function public.confirm_booking_payment(uuid, text, jsonb) from public, anon, authenticated;
revoke execute on function public.mark_payment_failed(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.release_expired_holds() from public, anon, authenticated;
grant execute on function public.confirm_booking_payment(uuid, text, jsonb) to service_role;
grant execute on function public.mark_payment_failed(uuid, jsonb) to service_role;
grant execute on function public.release_expired_holds() to service_role;

revoke execute on function public.create_booking_hold(uuid, timestamptz, uuid, uuid, integer) from public, anon;
revoke execute on function public.cancel_booking(uuid) from public, anon;
revoke execute on function public.set_booking_outcome(uuid, public.booking_status) from public, anon;
revoke execute on function public.verify_ticket(text) from public, anon;
