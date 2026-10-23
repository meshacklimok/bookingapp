-- Row Level Security.
-- Bookings, tickets, payments and commission fields are written only by the SECURITY DEFINER
-- functions and Edge Functions, so clients get read access only on those tables.

alter table public.profiles enable row level security;
alter table public.organizations enable row level security;
alter table public.org_members enable row level security;
alter table public.services enable row level security;
alter table public.staff_services enable row level security;
alter table public.availability_rules enable row level security;
alter table public.availability_exceptions enable row level security;
alter table public.ticket_tiers enable row level security;
alter table public.bookings enable row level security;
alter table public.tickets enable row level security;
alter table public.payments enable row level security;
alter table public.refunds enable row level security;
alter table public.commission_settings enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notifications enable row level security;

-- profiles
create policy profiles_select on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or public.is_platform_admin()
    or exists (
      select 1 from public.bookings b
       where b.customer_id = profiles.id and public.is_org_member(b.org_id)
    )
    or exists (
      select 1 from public.org_members m
       where m.user_id = profiles.id
         and m.org_id in (select org_id from public.org_members where user_id = auth.uid())
    )
  );
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and is_platform_admin = public.is_platform_admin());

-- organizations
create policy organizations_select on public.organizations for select
  using (status = 'approved' or public.is_org_member(id) or public.is_platform_admin());
create policy organizations_insert on public.organizations for insert to authenticated
  with check (created_by = auth.uid() and status = 'pending');
create policy organizations_update on public.organizations for update to authenticated
  using (public.is_org_member(id, array['owner', 'admin']::public.org_role[]) or public.is_platform_admin());

create function public.protect_org_status() returns trigger
language plpgsql as $$
begin
  if new.status is distinct from old.status and auth.uid() is not null and not public.is_platform_admin() then
    raise exception 'only platform admins can change organization status' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger organizations_protect_status
  before update on public.organizations
  for each row execute function public.protect_org_status();

-- org_members
create policy org_members_select on public.org_members for select to authenticated
  using (user_id = auth.uid() or public.is_org_member(org_id) or public.is_platform_admin());
create policy org_members_write on public.org_members for all to authenticated
  using (public.is_org_member(org_id, array['owner', 'admin']::public.org_role[]))
  with check (public.is_org_member(org_id, array['owner', 'admin']::public.org_role[]));

-- services
create policy services_select on public.services for select
  using (
    (is_active and exists (select 1 from public.organizations o where o.id = org_id and o.status = 'approved'))
    or public.is_org_member(org_id)
    or public.is_platform_admin()
  );
create policy services_write on public.services for all to authenticated
  using (public.is_org_member(org_id, array['owner', 'admin']::public.org_role[]))
  with check (public.is_org_member(org_id, array['owner', 'admin']::public.org_role[]));

-- staff_services
create policy staff_services_select on public.staff_services for select
  using (true);
create policy staff_services_write on public.staff_services for all to authenticated
  using (exists (select 1 from public.services s
                  where s.id = service_id and public.is_org_member(s.org_id, array['owner', 'admin']::public.org_role[])))
  with check (exists (select 1 from public.services s
                       where s.id = service_id and public.is_org_member(s.org_id, array['owner', 'admin']::public.org_role[])));

-- availability
create policy availability_rules_select on public.availability_rules for select to authenticated
  using (public.is_org_member(org_id) or public.is_platform_admin());
create policy availability_rules_write on public.availability_rules for all to authenticated
  using (public.is_org_member(org_id, array['owner', 'admin']::public.org_role[]))
  with check (public.is_org_member(org_id, array['owner', 'admin']::public.org_role[]));

create policy availability_exceptions_select on public.availability_exceptions for select to authenticated
  using (public.is_org_member(org_id) or public.is_platform_admin());
create policy availability_exceptions_write on public.availability_exceptions for all to authenticated
  using (public.is_org_member(org_id, array['owner', 'admin']::public.org_role[]))
  with check (public.is_org_member(org_id, array['owner', 'admin']::public.org_role[]));

-- ticket_tiers (sold is changed only by create_booking_hold; org admins manage the rest)
create policy ticket_tiers_select on public.ticket_tiers for select
  using (exists (select 1 from public.services s where s.id = service_id));
create policy ticket_tiers_write on public.ticket_tiers for all to authenticated
  using (exists (select 1 from public.services s
                  where s.id = service_id and public.is_org_member(s.org_id, array['owner', 'admin']::public.org_role[])))
  with check (exists (select 1 from public.services s
                       where s.id = service_id and public.is_org_member(s.org_id, array['owner', 'admin']::public.org_role[])));

-- bookings, tickets, payments: read only
create policy bookings_select on public.bookings for select to authenticated
  using (customer_id = auth.uid() or public.is_org_member(org_id) or public.is_platform_admin());
create policy tickets_select on public.tickets for select to authenticated
  using (customer_id = auth.uid() or public.is_org_member(org_id) or public.is_platform_admin());
create policy payments_select on public.payments for select to authenticated
  using (customer_id = auth.uid() or public.is_org_member(org_id, array['owner', 'admin']::public.org_role[]) or public.is_platform_admin());
create policy refunds_select on public.refunds for select to authenticated
  using (public.is_platform_admin());

-- commission settings: platform admins only
create policy commission_settings_all on public.commission_settings for all to authenticated
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

-- device tokens and notifications
create policy device_tokens_own on public.device_tokens for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy notifications_select on public.notifications for select to authenticated
  using (user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Realtime: the app watches its booking and tickets while a payment completes.
alter publication supabase_realtime add table public.bookings;
alter publication supabase_realtime add table public.tickets;
