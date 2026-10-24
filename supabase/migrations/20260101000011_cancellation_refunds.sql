-- Cancellation policies, cancelling paid bookings, and refunds -------------------------------------------------------------
-- Policy per service: a full refund until `free_cancel_hours` before the start, `late_refund_pct` percent after that.
-- When the organization cancels, the customer always gets everything back.
-- Commission is reversed pro rata with the refund. The booking keeps total_cents (what the customer paid) and records
-- refund_cents; commission_cents / org_earnings_cents are rewritten to describe what is left after the refund.
-- The provider payout of a refund is manual for now: a `pending` refunds row is created and a platform admin marks it
-- processed once the money has been sent back (resolve_refund).

alter table public.services
  add column free_cancel_hours integer not null default 24 check (free_cancel_hours between 0 and 720),
  add column late_refund_pct integer not null default 0 check (late_refund_pct between 0 and 100);

alter table public.bookings
  add column refund_cents bigint not null default 0,
  add column cancelled_at timestamptz,
  add column cancelled_by uuid references public.profiles (id),
  add column cancel_reason text,
  add constraint bookings_refund_within_total check (refund_cents between 0 and total_cents);

alter table public.refunds
  add column processed_at timestamptz,
  add column provider_ref text,
  add constraint refunds_status_check check (status in ('pending', 'processed', 'failed'));
create index refunds_payment_idx on public.refunds (payment_id);

-- customers see their own refunds, organization owners and admins see their organization's
drop policy refunds_select on public.refunds;
create policy refunds_select on public.refunds for select to authenticated
  using (exists (
    select 1 from public.payments p
     where p.id = refunds.payment_id
       and (p.customer_id = auth.uid()
            or public.is_org_member(p.org_id, array['owner', 'admin']::public.org_role[])
            or public.is_platform_admin())
  ));

-- How much would come back if the caller cancelled this booking now? Not an exposed function: cancel_booking and
-- cancellation_quote both use it.
create function public.compute_refund(p_total bigint, p_starts_at timestamptz, p_free_hours integer, p_late_pct integer, p_by_org boolean)
returns bigint
language sql stable as $$
  select case
    when p_by_org then p_total
    when p_starts_at - make_interval(hours => p_free_hours) >= now() then p_total
    else round(p_total * p_late_pct / 100.0)::bigint
  end
$$;
revoke execute on function public.compute_refund(bigint, timestamptz, integer, integer, boolean) from public, anon, authenticated;

-- What the customer or the organization would get back, so the app can show it before they confirm.
create function public.cancellation_quote(p_booking_id uuid)
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
  if b.customer_id <> auth.uid() and not v_by_org then
    raise exception 'cannot_cancel';
  end if;
  select * into s from public.services where id = b.service_id;
  v_refund := case when b.status = 'confirmed'
                   then public.compute_refund(b.total_cents, b.starts_at, s.free_cancel_hours, s.late_refund_pct, v_by_org)
                   else 0 end;
  return query select v_refund, v_refund = b.total_cents, v_by_org;
end $$;

-- Replaces the unpaid-only version. Unpaid holds can only be dropped by the customer, exactly as before.
drop function public.cancel_booking(uuid);
create function public.cancel_booking(p_booking_id uuid, p_reason text default null) returns void
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
  if b.customer_id <> v_uid and not v_by_org then
    raise exception 'cannot_cancel';
  end if;

  if b.status in ('held', 'pending_payment') then
    if b.customer_id <> v_uid then
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
  v_refund := public.compute_refund(b.total_cents, b.starts_at, s.free_cancel_hours, s.late_refund_pct, v_by_org);
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
      values (v_payment, v_refund, case when v_by_org and b.customer_id <> v_uid then 'cancelled by organization' else 'cancelled by customer' end);
    end if;
  end if;

  select title into v_title from public.services where id = b.service_id;
  if v_by_org and b.customer_id <> v_uid then
    insert into public.notifications (user_id, title, body, data)
    values (b.customer_id, 'Booking cancelled by the organizer',
            v_title || ' was cancelled. You will be refunded in full.',
            jsonb_build_object('booking_id', b.id, 'route', '/bookings'));
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

-- Platform admin records that a refund was paid out (or failed). A payment becomes `refunded` once fully refunded.
create function public.resolve_refund(p_refund_id uuid, p_status text, p_provider_ref text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.refunds%rowtype;
  v_pay public.payments%rowtype;
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_status not in ('processed', 'failed') then
    raise exception 'invalid_status';
  end if;
  select * into r from public.refunds where id = p_refund_id for update;
  if not found or r.status <> 'pending' then
    raise exception 'refund_not_pending';
  end if;
  update public.refunds
     set status = p_status, provider_ref = p_provider_ref, processed_at = now()
   where id = r.id;
  if p_status = 'processed' then
    select * into v_pay from public.payments where id = r.payment_id for update;
    if (select coalesce(sum(amount_cents), 0) from public.refunds where payment_id = v_pay.id and status = 'processed') >= v_pay.amount_cents then
      update public.payments set status = 'refunded', updated_at = now() where id = v_pay.id;
    end if;
    insert into public.notifications (user_id, title, body, data)
    values (v_pay.customer_id, 'Refund sent', 'Your refund has been paid out.', jsonb_build_object('refund_id', r.id, 'route', '/bookings'));
  end if;
end $$;
revoke execute on function public.resolve_refund(uuid, text, text) from public, anon;
grant execute on function public.resolve_refund(uuid, text, text) to authenticated;

-- Earnings now net of refunds. A cancelled booking still counts for what the organization kept (a late cancellation
-- with a partial or no refund); fully refunded bookings have nothing left and drop out.
drop function public.org_earnings_summary(uuid, date, date);
drop function public.org_earnings_rows(uuid, date, date, integer);

create function public.org_earnings_summary(p_org_id uuid, p_from date default null, p_to date default null)
returns table (booking_count bigint, gross_cents bigint, commission_cents bigint, net_cents bigint, refunded_cents bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_org_member(p_org_id, array['owner', 'admin']::public.org_role[]) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
  select count(*),
         coalesce(sum(b.total_cents - b.refund_cents), 0)::bigint,
         coalesce(sum(b.commission_cents), 0)::bigint,
         coalesce(sum(b.org_earnings_cents), 0)::bigint,
         coalesce(sum(b.refund_cents), 0)::bigint
    from public.bookings b
   where b.org_id = p_org_id
     and b.commission_cents is not null
     and b.status in ('confirmed', 'completed', 'no_show', 'cancelled')
     and b.total_cents - b.refund_cents > 0
     and (p_from is null or (b.starts_at at time zone 'Africa/Nairobi')::date >= p_from)
     and (p_to is null or (b.starts_at at time zone 'Africa/Nairobi')::date <= p_to);
end $$;

create function public.org_earnings_rows(p_org_id uuid, p_from date default null, p_to date default null, p_limit integer default 200)
returns table (
  booking_id uuid,
  starts_at timestamptz,
  status public.booking_status,
  service_title text,
  customer_name text,
  gross_cents bigint,
  commission_pct numeric,
  commission_cents bigint,
  net_cents bigint,
  refund_cents bigint
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_org_member(p_org_id, array['owner', 'admin']::public.org_role[]) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
  select b.id, b.starts_at, b.status, s.title, p.full_name,
         b.total_cents - b.refund_cents, b.commission_pct, b.commission_cents, b.org_earnings_cents, b.refund_cents
    from public.bookings b
    join public.services s on s.id = b.service_id
    left join public.profiles p on p.id = b.customer_id
   where b.org_id = p_org_id
     and b.commission_cents is not null
     and b.status in ('confirmed', 'completed', 'no_show', 'cancelled')
     and b.total_cents - b.refund_cents > 0
     and (p_from is null or (b.starts_at at time zone 'Africa/Nairobi')::date >= p_from)
     and (p_to is null or (b.starts_at at time zone 'Africa/Nairobi')::date <= p_to)
   order by b.starts_at desc
   limit least(greatest(p_limit, 1), 500);
end $$;

revoke execute on function public.org_earnings_summary(uuid, date, date) from public, anon;
revoke execute on function public.org_earnings_rows(uuid, date, date, integer) from public, anon;
grant execute on function public.org_earnings_summary(uuid, date, date) to authenticated;
grant execute on function public.org_earnings_rows(uuid, date, date, integer) to authenticated;
