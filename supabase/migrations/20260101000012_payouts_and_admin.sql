-- Payouts ledger and platform-admin controls ------------------------------------------------------------------------------
-- What the platform owes an organization = its net earnings that are settled, minus what was already paid out.
-- Settled means the booking is over (ends_at has passed) or it was cancelled with money kept (late cancellation).
-- Upcoming confirmed bookings are shown separately because they can still be cancelled and refunded.
-- Payouts are recorded by a platform admin after sending the money (M-Pesa, bank transfer); nothing here moves money.

create table public.payouts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id),
  amount_cents bigint not null check (amount_cents > 0),
  method text not null check (method in ('mpesa', 'bank', 'other')),
  reference text,
  note text,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);
create index payouts_org_idx on public.payouts (org_id, created_at desc);

alter table public.payouts enable row level security;
create policy payouts_select on public.payouts for select to authenticated
  using (public.is_org_member(org_id, array['owner', 'admin']::public.org_role[]) or public.is_platform_admin());

-- No authorization here: callers below check it.
create function public.org_balance_calc(p_org_id uuid)
returns table (payable_cents bigint, upcoming_cents bigint, paid_out_cents bigint)
language sql stable security definer set search_path = public as $$
  with earned as (
    select b.org_earnings_cents as net, (b.status = 'cancelled' or b.ends_at <= now()) as settled
      from public.bookings b
     where b.org_id = p_org_id
       and b.commission_cents is not null
       and b.status in ('confirmed', 'completed', 'no_show', 'cancelled')
       and b.total_cents - b.refund_cents > 0
  ), paid as (
    select coalesce(sum(amount_cents), 0)::bigint as total from public.payouts where org_id = p_org_id
  )
  select coalesce((select sum(net) from earned where settled), 0)::bigint - (select total from paid),
         coalesce((select sum(net) from earned where not settled), 0)::bigint,
         (select total from paid)
$$;
revoke execute on function public.org_balance_calc(uuid) from public, anon, authenticated;

create function public.org_balance(p_org_id uuid)
returns table (payable_cents bigint, upcoming_cents bigint, paid_out_cents bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_org_member(p_org_id, array['owner', 'admin']::public.org_role[]) or public.is_platform_admin()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query select * from public.org_balance_calc(p_org_id);
end $$;
revoke execute on function public.org_balance(uuid) from public, anon;
grant execute on function public.org_balance(uuid) to authenticated;

-- Platform admin: every organization that is owed money or has upcoming earnings.
create function public.admin_org_balances()
returns table (org_id uuid, org_name text, payable_cents bigint, upcoming_cents bigint, paid_out_cents bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
  select o.id, o.name, c.payable_cents, c.upcoming_cents, c.paid_out_cents
    from public.organizations o
    cross join lateral public.org_balance_calc(o.id) c
   where c.payable_cents <> 0 or c.upcoming_cents <> 0 or c.paid_out_cents <> 0
   order by c.payable_cents desc, o.name;
end $$;
revoke execute on function public.admin_org_balances() from public, anon;
grant execute on function public.admin_org_balances() to authenticated;

create function public.record_payout(p_org_id uuid, p_amount_cents bigint, p_method text, p_reference text default null, p_note text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_payable bigint;
  v_id uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  -- serialize payouts per organization so two admins cannot both pay the same balance
  perform 1 from public.organizations where id = p_org_id for update;
  if not found then
    raise exception 'org_not_found';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'invalid_amount';
  end if;
  select payable_cents into v_payable from public.org_balance_calc(p_org_id);
  if p_amount_cents > v_payable then
    raise exception 'exceeds_balance';
  end if;
  insert into public.payouts (org_id, amount_cents, method, reference, note, created_by)
  values (p_org_id, p_amount_cents, p_method, nullif(btrim(p_reference), ''), nullif(btrim(p_note), ''), auth.uid())
  returning id into v_id;
  insert into public.notifications (user_id, title, body, data)
  select m.user_id, 'Payout sent', 'A payout of KES ' || (p_amount_cents / 100) || ' was sent to your organization.',
         jsonb_build_object('payout_id', v_id, 'route', '/org/' || p_org_id || '/payouts')
    from public.org_members m
   where m.org_id = p_org_id and m.role in ('owner', 'admin');
  return v_id;
end $$;
revoke execute on function public.record_payout(uuid, bigint, text, text, text) from public, anon;
grant execute on function public.record_payout(uuid, bigint, text, text, text) to authenticated;

-- Commission rates ------------------------------------------------------------------------------------------------------
-- The unique index treats the platform row's null scope_id specially, so writes go through these functions.
create function public.set_commission(p_scope public.commission_scope, p_scope_id uuid, p_pct numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_pct is null or p_pct < 0 or p_pct > 100 then
    raise exception 'invalid_pct';
  end if;
  if (p_scope = 'platform') <> (p_scope_id is null) then
    raise exception 'invalid_scope';
  end if;
  if p_scope = 'org' and not exists (select 1 from public.organizations where id = p_scope_id)
     or p_scope = 'service' and not exists (select 1 from public.services where id = p_scope_id) then
    raise exception 'invalid_scope';
  end if;
  update public.commission_settings set pct = p_pct
   where scope = p_scope and scope_id is not distinct from p_scope_id;
  if not found then
    insert into public.commission_settings (scope, scope_id, pct) values (p_scope, p_scope_id, p_pct);
  end if;
end $$;

-- Removing an override falls back to the next level. The platform default itself cannot be removed.
create function public.clear_commission(p_scope public.commission_scope, p_scope_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_scope = 'platform' then
    raise exception 'invalid_scope';
  end if;
  delete from public.commission_settings where scope = p_scope and scope_id = p_scope_id;
end $$;

create function public.admin_commissions()
returns table (scope public.commission_scope, scope_id uuid, name text, pct numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
  select c.scope, c.scope_id,
         case c.scope when 'platform' then 'Platform default'
                      when 'org' then (select o.name from public.organizations o where o.id = c.scope_id)
                      else (select s.title from public.services s where s.id = c.scope_id) end,
         c.pct
    from public.commission_settings c
   order by case c.scope when 'platform' then 0 when 'org' then 1 else 2 end, 3;
end $$;

revoke execute on function public.set_commission(public.commission_scope, uuid, numeric) from public, anon;
revoke execute on function public.clear_commission(public.commission_scope, uuid) from public, anon;
revoke execute on function public.admin_commissions() from public, anon;
grant execute on function public.set_commission(public.commission_scope, uuid, numeric) to authenticated;
grant execute on function public.clear_commission(public.commission_scope, uuid) to authenticated;
grant execute on function public.admin_commissions() to authenticated;
