-- Deposits / partial payments ---------------------------------------------------------------------------------------------
-- A service can ask for a deposit (deposit_pct of the price). The customer chooses at checkout to pay only the deposit
-- online; the rest is paid to the organization at the venue.
--
-- The booking keeps total_cents as "what is charged online". That keeps payments, commission, refunds and the earnings
-- ledger unchanged: they all describe money the platform actually collected. The part still owed at the venue lives in
-- balance_cents, so the full price is total_cents + balance_cents (like discount_cents for promo codes). Commission is
-- taken on the deposit only, because the platform never handles the balance. Cancelling refunds by the cancellation
-- policy of the deposit; the balance simply never becomes due.

alter table public.services
  add column deposit_pct integer check (deposit_pct between 1 and 99);

alter table public.bookings
  add column balance_cents bigint not null default 0 check (balance_cents >= 0),
  add column balance_paid_at timestamptz;

-- Moves a held booking between "pay everything now" and "pay the deposit now, the rest at the venue". Always computed
-- from the full price, so choosing again (or after a promo code changes) gives the same answer. Whole shillings, as M-Pesa
-- only takes whole amounts.
create function public.set_payment_plan(p_booking_id uuid, p_deposit boolean) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  b public.bookings%rowtype;
  v_pct integer;
  v_full bigint;
  v_now bigint;
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

  v_full := b.total_cents + b.balance_cents;
  if p_deposit then
    select deposit_pct into v_pct from public.services where id = b.service_id;
    if v_pct is null then
      raise exception 'deposit_not_offered';
    end if;
    if v_full = 0 then
      raise exception 'booking_free';
    end if;
    v_now := least(v_full, (ceil(v_full * v_pct / 10000.0) * 100)::bigint);
  else
    v_now := v_full;
  end if;

  update public.bookings set total_cents = v_now, balance_cents = v_full - v_now where id = b.id returning * into b;
  return b;
end $$;
revoke execute on function public.set_payment_plan(uuid, boolean) from public, anon;
grant execute on function public.set_payment_plan(uuid, boolean) to authenticated;

-- A promo code applies to the full price, so any deposit plan is folded back first; the app asks for it again after.
create or replace function public.apply_promo_code(p_booking_id uuid, p_code text) returns public.bookings
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

  v_base := b.total_cents + b.balance_cents + b.discount_cents;
  v_discount := least(
    v_base,
    case when p.percent_off is not null then round(v_base * p.percent_off / 100.0)::bigint else p.amount_off_cents end
  );
  update public.bookings
     set promo_code_id = p.id, discount_cents = v_discount, total_cents = v_base - v_discount, balance_cents = 0
   where id = b.id
  returning * into b;
  return b;
end $$;

create or replace function public.remove_promo_code(p_booking_id uuid) returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings%rowtype;
begin
  update public.bookings
     set promo_code_id = null, total_cents = total_cents + balance_cents + discount_cents, balance_cents = 0, discount_cents = 0
   where id = p_booking_id and customer_id = auth.uid() and status = 'held'
  returning * into b;
  if not found then
    raise exception 'cannot_apply';
  end if;
  return b;
end $$;

-- The organization records that the customer paid the balance at the venue.
create function public.mark_balance_paid(p_booking_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
begin
  select org_id into v_org from public.bookings where id = p_booking_id;
  if v_org is null or not public.is_org_member(v_org) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update public.bookings
     set balance_paid_at = now()
   where id = p_booking_id
     and status in ('confirmed', 'completed')
     and balance_cents > 0
     and balance_paid_at is null;
  if not found then
    raise exception 'no_balance_due';
  end if;
end $$;
revoke execute on function public.mark_balance_paid(uuid) from public, anon;
grant execute on function public.mark_balance_paid(uuid) to authenticated;

-- Check-in also tells the door staff what is still owed. Guests booked by the organization have no profile.
create or replace function public.verify_ticket(p_qr_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_ticket public.tickets%rowtype;
  v_title text;
  v_holder text;
  v_starts timestamptz;
  v_due bigint;
begin
  select * into v_ticket from public.tickets where qr_token = p_qr_token;
  if not found then
    return jsonb_build_object('result', 'invalid');
  end if;
  if auth.uid() is null or not public.is_org_member(v_ticket.org_id) then
    return jsonb_build_object('result', 'forbidden');
  end if;

  select s.title, b.starts_at, coalesce(p.full_name, b.guest_name),
         case when b.balance_paid_at is null then b.balance_cents else 0 end
    into v_title, v_starts, v_holder, v_due
    from public.bookings b
    join public.services s on s.id = b.service_id
    left join public.profiles p on p.id = b.customer_id
   where b.id = v_ticket.booking_id;

  update public.tickets
     set status = 'used', checked_in_at = now(), checked_in_by = auth.uid()
   where id = v_ticket.id and status = 'valid';

  if found then
    return jsonb_build_object('result', 'ok', 'service', v_title, 'holder', v_holder, 'starts_at', v_starts,
                              'balance_due_cents', v_due);
  end if;

  select * into v_ticket from public.tickets where id = v_ticket.id;
  return jsonb_build_object(
    'result', case when v_ticket.status = 'used' then 'already_used' else 'void' end,
    'service', v_title,
    'checked_in_at', v_ticket.checked_in_at
  );
end $$;
