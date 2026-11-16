-- Resource bookings, promo codes and reviews --------------------------------------------------------------------------

-- Resources ----------------------------------------------------------------------------------------------------------
-- A resource (court, room, vehicle) is booked in fixed slots of duration_min (+ buffer_min) between its opening and
-- closing time, in Africa/Nairobi, every day. The booking's exclusive_key is the service, so one slot has one booker.
alter table public.services
  add column open_time time not null default '08:00',
  add column close_time time not null default '20:00',
  add constraint services_hours_check check (close_time > open_time);

create function public.get_resource_slots(p_service_id uuid, p_date date)
returns table (staff_id uuid, slot_start timestamptz, slot_end timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  v_service public.services%rowtype;
  v_tz constant text := 'Africa/Nairobi';
  v_duration interval;
  v_step interval;
begin
  select s.* into v_service
    from public.services s
    join public.organizations o on o.id = s.org_id
   where s.id = p_service_id and s.is_active and s.booking_mode = 'resource' and o.status = 'approved';
  if not found then
    return;
  end if;

  v_duration := make_interval(mins => v_service.duration_min);
  v_step := make_interval(mins => v_service.duration_min + v_service.buffer_min);

  return query
  select null::uuid, g, g + v_duration
    from generate_series(
           ((p_date + v_service.open_time) at time zone v_tz),
           ((p_date + v_service.close_time) at time zone v_tz) - v_duration,
           v_step) g
   where g >= now()
     and not exists (
       select 1 from public.bookings b
        where b.exclusive_key = p_service_id
          and b.status in ('held', 'pending_payment', 'confirmed')
          and (b.status = 'confirmed' or b.expires_at > now())
          and b.time_range && tstzrange(g, g + v_step, '[)')
     )
   order by g;
end $$;

-- Same as before, plus the resource branch.
create or replace function public.create_booking_hold(
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
  v_staff uuid;
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
    v_staff := p_staff_id;
    v_total := v_service.price_cents;

  elsif v_service.booking_mode = 'resource' then
    if p_starts_at is null then
      raise exception 'slot_required';
    end if;
    if not exists (
      select 1
        from public.get_resource_slots(p_service_id, (p_starts_at at time zone 'Africa/Nairobi')::date) g
       where g.slot_start = p_starts_at
    ) then
      raise exception 'slot_unavailable';
    end if;
    v_qty := 1;
    v_starts := p_starts_at;
    v_ends := p_starts_at + make_interval(mins => v_service.duration_min + v_service.buffer_min);
    v_key := v_service.id;
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
      v_uid, v_service.id, v_service.org_id, v_staff, p_tier_id, v_starts, v_ends,
      v_qty, 'held', now() + interval '10 minutes', v_total, v_key
    ) returning * into v_booking;
  exception when exclusion_violation then
    raise exception 'slot_unavailable';
  end;

  return v_booking;
end $$;

-- Promo codes --------------------------------------------------------------------------------------------------------
-- A code belongs to one organization and takes a percentage or a fixed amount off a booking at checkout. The booking
-- keeps the discount, so total_cents is what is charged and total_cents + discount_cents is the list price.
-- The organization funds the discount: commission is taken on what the customer actually paid.
create table public.promo_codes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  code text not null check (code ~ '^[A-Za-z0-9_-]{3,24}$'),
  percent_off integer check (percent_off between 1 and 100),
  amount_off_cents integer check (amount_off_cents > 0),
  max_uses integer check (max_uses > 0),
  valid_from timestamptz,
  valid_until timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check ((percent_off is null) <> (amount_off_cents is null)),
  check (valid_until is null or valid_from is null or valid_until > valid_from)
);
create unique index promo_codes_code_idx on public.promo_codes (org_id, upper(code));

alter table public.promo_codes enable row level security;
create policy promo_codes_select on public.promo_codes for select to authenticated
  using (public.is_org_member(org_id) or public.is_platform_admin());
create policy promo_codes_write on public.promo_codes for all to authenticated
  using (public.is_org_member(org_id, array['owner', 'admin']::public.org_role[]))
  with check (public.is_org_member(org_id, array['owner', 'admin']::public.org_role[]));

alter table public.bookings
  add column promo_code_id uuid references public.promo_codes (id) on delete set null,
  add column discount_cents bigint not null default 0 check (discount_cents >= 0);

-- Bookings that use up a code: paid ones, and live holds (so two people cannot grab the last use at once).
create function public.promo_uses(p_promo_id uuid, p_except_booking uuid default null, p_customer uuid default null)
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::integer from public.bookings b
   where b.promo_code_id = p_promo_id
     and b.id is distinct from p_except_booking
     and (p_customer is null or b.customer_id = p_customer)
     and (b.status in ('confirmed', 'completed', 'no_show')
          or (b.status in ('held', 'pending_payment') and b.expires_at > now()))
$$;
revoke execute on function public.promo_uses(uuid, uuid, uuid) from public, anon, authenticated;

-- Applies (or swaps) a code on the caller's own unpaid hold. Everything is computed here from the stored list price.
create function public.apply_promo_code(p_booking_id uuid, p_code text) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  b public.bookings%rowtype;
  p public.promo_codes%rowtype;
  v_base bigint;
  v_discount bigint;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into b from public.bookings where id = p_booking_id and customer_id = v_uid for update;
  if not found then
    raise exception 'booking_not_found';
  end if;
  if b.status <> 'held' or b.expires_at < now() then
    raise exception 'cannot_apply';
  end if;

  select * into p from public.promo_codes where org_id = b.org_id and upper(code) = upper(btrim(p_code)) for update;
  if not found or not p.is_active then
    raise exception 'promo_invalid';
  end if;
  if (p.valid_from is not null and now() < p.valid_from) or (p.valid_until is not null and now() > p.valid_until) then
    raise exception 'promo_expired';
  end if;
  if public.promo_uses(p.id, b.id, v_uid) > 0 then
    raise exception 'promo_already_used';
  end if;
  if p.max_uses is not null and public.promo_uses(p.id, b.id) >= p.max_uses then
    raise exception 'promo_used_up';
  end if;

  v_base := b.total_cents + b.discount_cents;
  v_discount := least(
    v_base,
    case when p.percent_off is not null then round(v_base * p.percent_off / 100.0)::bigint else p.amount_off_cents end
  );
  update public.bookings
     set promo_code_id = p.id, discount_cents = v_discount, total_cents = v_base - v_discount
   where id = b.id
  returning * into b;
  return b;
end $$;

create function public.remove_promo_code(p_booking_id uuid) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings%rowtype;
begin
  update public.bookings
     set promo_code_id = null, total_cents = total_cents + discount_cents, discount_cents = 0
   where id = p_booking_id and customer_id = auth.uid() and status = 'held'
  returning * into b;
  if not found then
    raise exception 'cannot_apply';
  end if;
  return b;
end $$;

-- A booking that costs nothing (a free service, or a code that covers all of it) needs no payment: the customer
-- confirms it directly. Same effect as confirm_booking_payment, without a payment row.
create function public.confirm_free_booking(p_booking_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings%rowtype;
begin
  select * into b from public.bookings where id = p_booking_id and customer_id = auth.uid() for update;
  if not found then
    raise exception 'booking_not_found';
  end if;
  if b.status = 'confirmed' then
    return;
  end if;
  if b.total_cents <> 0 then
    raise exception 'booking_not_free';
  end if;
  if b.status <> 'held' or b.expires_at < now() then
    raise exception 'cannot_confirm';
  end if;

  update public.bookings
     set status = 'confirmed', expires_at = null,
         commission_pct = public.resolve_commission_pct(b.service_id), commission_cents = 0, org_earnings_cents = 0
   where id = b.id;
  insert into public.tickets (booking_id, org_id, customer_id)
  select b.id, b.org_id, b.customer_id from generate_series(1, case when b.tier_id is not null then b.quantity else 1 end);
end $$;

-- The organization's codes with how many times each has been used.
create function public.org_promo_codes(p_org_id uuid)
returns table (id uuid, code text, percent_off integer, amount_off_cents integer, max_uses integer,
               valid_until timestamptz, is_active boolean, uses integer)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
  select p.id, p.code, p.percent_off, p.amount_off_cents, p.max_uses, p.valid_until, p.is_active,
         public.promo_uses(p.id)
    from public.promo_codes p
   where p.org_id = p_org_id
   order by p.created_at desc;
end $$;

-- Reviews ------------------------------------------------------------------------------------------------------------
-- One review per booking, written by the customer once the booking has ended. Only the functions below write them.
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings (id) on delete cascade,
  service_id uuid not null references public.services (id) on delete cascade,
  org_id uuid not null references public.organizations (id) on delete cascade,
  customer_id uuid not null references public.profiles (id),
  rating smallint not null check (rating between 1 and 5),
  comment text check (char_length(comment) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index reviews_service_idx on public.reviews (service_id, created_at desc);

alter table public.reviews enable row level security;
create policy reviews_select on public.reviews for select to authenticated
  using (customer_id = auth.uid() or public.is_org_member(org_id) or public.is_platform_admin());
revoke insert, update, delete on public.reviews from authenticated, anon;

-- Average and count on the service, so lists can show stars without joining.
alter table public.services
  add column rating_avg numeric(3, 2),
  add column rating_count integer not null default 0;

create function public.refresh_service_rating() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_service uuid := coalesce(new.service_id, old.service_id);
begin
  update public.services s
     set rating_count = r.c, rating_avg = r.a
    from (select count(*)::integer c, round(avg(rating), 2) a from public.reviews where service_id = v_service) r
   where s.id = v_service;
  return null;
end $$;
create trigger reviews_refresh_rating
  after insert or update or delete on public.reviews
  for each row execute function public.refresh_service_rating();

create function public.submit_review(p_booking_id uuid, p_rating integer, p_comment text default null)
returns public.reviews
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  b public.bookings%rowtype;
  r public.reviews%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'invalid_rating';
  end if;
  select * into b from public.bookings where id = p_booking_id and customer_id = v_uid;
  if not found or b.status not in ('confirmed', 'completed') or b.ends_at > now() then
    raise exception 'cannot_review';
  end if;
  insert into public.reviews (booking_id, service_id, org_id, customer_id, rating, comment)
  values (b.id, b.service_id, b.org_id, v_uid, p_rating, nullif(btrim(p_comment), ''))
  on conflict (booking_id) do update
    set rating = excluded.rating, comment = excluded.comment, updated_at = now()
  returning * into r;
  return r;
end $$;

-- What other customers see: the rating, the text and a first name.
create function public.get_service_reviews(p_service_id uuid, p_limit integer default 20)
returns table (rating smallint, comment text, created_at timestamptz, reviewer text)
language sql stable security definer set search_path = public as $$
  select r.rating, r.comment, r.created_at,
         coalesce(nullif(split_part(btrim(p.full_name), ' ', 1), ''), 'Customer')
    from public.reviews r
    join public.profiles p on p.id = r.customer_id
    join public.services s on s.id = r.service_id
    join public.organizations o on o.id = s.org_id
   where r.service_id = p_service_id and s.is_active and o.status = 'approved'
   order by r.created_at desc
   limit least(coalesce(p_limit, 20), 50)
$$;

-- Execution rights ---------------------------------------------------------------------------------------------------
revoke execute on function public.apply_promo_code(uuid, text) from public, anon;
revoke execute on function public.remove_promo_code(uuid) from public, anon;
revoke execute on function public.confirm_free_booking(uuid) from public, anon;
revoke execute on function public.org_promo_codes(uuid) from public, anon;
revoke execute on function public.submit_review(uuid, integer, text) from public, anon;
revoke execute on function public.refresh_service_rating() from public, anon, authenticated;
