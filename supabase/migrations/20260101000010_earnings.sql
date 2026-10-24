-- Earnings: gross, commission and net per booking and in total ------------------------------------------------------------
-- A booking counts as earned once it was paid (the commission snapshot is set by confirm_booking_payment) and was not
-- cancelled. No-shows stay in because the customer paid and nothing here refunds them.
-- Only owners and admins may read these figures; the raw columns stay readable to every member through the bookings
-- policy, so this is a convenience for the dashboard rather than a hard secrecy boundary.
-- p_from / p_to are inclusive Africa/Nairobi dates on the booking's start; null leaves that side open.

create function public.org_earnings_summary(p_org_id uuid, p_from date default null, p_to date default null)
returns table (booking_count bigint, gross_cents bigint, commission_cents bigint, net_cents bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_org_member(p_org_id, array['owner', 'admin']::public.org_role[]) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
  select count(*),
         coalesce(sum(b.total_cents), 0)::bigint,
         coalesce(sum(b.commission_cents), 0)::bigint,
         coalesce(sum(b.org_earnings_cents), 0)::bigint
    from public.bookings b
   where b.org_id = p_org_id
     and b.commission_cents is not null
     and b.status in ('confirmed', 'completed', 'no_show')
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
  net_cents bigint
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_org_member(p_org_id, array['owner', 'admin']::public.org_role[]) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
  select b.id, b.starts_at, b.status, s.title, p.full_name,
         b.total_cents, b.commission_pct, b.commission_cents, b.org_earnings_cents
    from public.bookings b
    join public.services s on s.id = b.service_id
    left join public.profiles p on p.id = b.customer_id
   where b.org_id = p_org_id
     and b.commission_cents is not null
     and b.status in ('confirmed', 'completed', 'no_show')
     and (p_from is null or (b.starts_at at time zone 'Africa/Nairobi')::date >= p_from)
     and (p_to is null or (b.starts_at at time zone 'Africa/Nairobi')::date <= p_to)
   order by b.starts_at desc
   limit least(greatest(p_limit, 1), 500);
end $$;

revoke execute on function public.org_earnings_summary(uuid, date, date) from public, anon;
revoke execute on function public.org_earnings_rows(uuid, date, date, integer) from public, anon;
grant execute on function public.org_earnings_summary(uuid, date, date) to authenticated;
grant execute on function public.org_earnings_rows(uuid, date, date, integer) to authenticated;
