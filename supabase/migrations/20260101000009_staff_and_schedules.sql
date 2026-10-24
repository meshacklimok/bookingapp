-- Staff and schedule management: who may be bookable, atomic weekly hours, and per-organization availability.

-- Only members of an organization can be its bookable staff ------------------------------------------------------
create function public.require_org_staff(p_org_id uuid, p_staff_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.org_members where org_id = p_org_id and user_id = p_staff_id) then
    raise exception 'not_org_member' using errcode = '23514';
  end if;
end $$;

create function public.check_staff_service_member() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_org_staff((select org_id from public.services where id = new.service_id), new.staff_id);
  return new;
end $$;
create trigger staff_services_require_member
  before insert or update on public.staff_services
  for each row execute function public.check_staff_service_member();

create function public.check_availability_member() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_org_staff(new.org_id, new.staff_id);
  return new;
end $$;
create trigger availability_rules_require_member
  before insert or update on public.availability_rules
  for each row execute function public.check_availability_member();
create trigger availability_exceptions_require_member
  before insert or update on public.availability_exceptions
  for each row execute function public.check_availability_member();

-- Removing a member -----------------------------------------------------------------------------------------------
-- Refuse while they have upcoming bookings; otherwise take them out of the slot picker for that organization.
create function public.on_org_member_removed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (
    select 1 from public.bookings b
     where b.org_id = old.org_id and b.staff_id = old.user_id and b.ends_at > now()
       and (b.status = 'confirmed' or (b.status in ('held', 'pending_payment') and b.expires_at > now()))
  ) then
    raise exception 'staff_has_bookings' using errcode = '23514';
  end if;
  delete from public.staff_services ss using public.services s
   where ss.service_id = s.id and s.org_id = old.org_id and ss.staff_id = old.user_id;
  delete from public.availability_rules where org_id = old.org_id and staff_id = old.user_id;
  delete from public.availability_exceptions where org_id = old.org_id and staff_id = old.user_id;
  return old;
end $$;
create trigger org_members_removed
  before delete on public.org_members
  for each row execute function public.on_org_member_removed();

-- Schedule integrity ----------------------------------------------------------------------------------------------
-- Windows on the same day must not overlap (adjacent is fine), or slots would be duplicated.
alter table public.availability_rules
  add constraint availability_rules_no_overlap exclude using gist (
    org_id with =, staff_id with =, weekday with =,
    tsrange(date '2000-01-01' + start_time, date '2000-01-01' + end_time) with &&
  );

-- A staff member working for two organizations has a separate day-off list for each.
alter table public.availability_exceptions drop constraint availability_exceptions_staff_id_date_key;
alter table public.availability_exceptions add constraint availability_exceptions_org_staff_date_key unique (org_id, staff_id, date);

-- Replaces a staff member's weekly hours in one transaction, so a bad payload never leaves them with none.
-- p_rules: [{"weekday": 1, "start_time": "09:00", "end_time": "17:00"}, ...] with weekday 0 = Sunday.
-- Runs as the caller, so row-level security still applies to the writes.
create function public.set_staff_hours(p_org_id uuid, p_staff_id uuid, p_rules jsonb) returns void
language plpgsql set search_path = public as $$
begin
  if not public.is_org_member(p_org_id, array['owner', 'admin']::public.org_role[]) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  delete from public.availability_rules where org_id = p_org_id and staff_id = p_staff_id;
  insert into public.availability_rules (org_id, staff_id, weekday, start_time, end_time)
  select p_org_id, p_staff_id, (r ->> 'weekday')::smallint, (r ->> 'start_time')::time, (r ->> 'end_time')::time
    from jsonb_array_elements(p_rules) r;
end $$;
revoke execute on function public.set_staff_hours(uuid, uuid, jsonb) from public, anon;
grant execute on function public.set_staff_hours(uuid, uuid, jsonb) to authenticated;

-- Adding staff by email --------------------------------------------------------------------------------------------
-- The person must already have an account. Profiles hold no email, so this looks it up in auth.users.
-- Callers are limited to owners and admins of the organization; they learn only whether the email has an account.
create function public.add_org_staff(p_org_id uuid, p_email text, p_role public.org_role default 'staff') returns uuid
language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid;
begin
  if not public.is_org_member(p_org_id, array['owner', 'admin']::public.org_role[]) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_role = 'owner' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select id into v_user from auth.users where lower(email) = lower(trim(p_email));
  if v_user is null then
    raise exception 'user_not_found';
  end if;
  if exists (select 1 from public.org_members where org_id = p_org_id and user_id = v_user) then
    raise exception 'already_member';
  end if;
  insert into public.org_members (org_id, user_id, role) values (p_org_id, v_user, p_role);
  return v_user;
end $$;
revoke execute on function public.add_org_staff(uuid, text, public.org_role) from public, anon;
grant execute on function public.add_org_staff(uuid, text, public.org_role) to authenticated;

-- Slots only use the hours and days off of the service's own organization ---------------------------------------------
create or replace function public.get_available_slots(p_service_id uuid, p_date date, p_staff_id uuid default null)
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
        on r.staff_id = st.sid and r.org_id = v_service.org_id and r.weekday = extract(dow from p_date)::smallint
     where not exists (
       select 1 from public.availability_exceptions e
        where e.staff_id = st.sid and e.org_id = v_service.org_id and e.date = p_date
     )
    union all
    select st.sid,
           (p_date + e.start_time) at time zone v_tz,
           (p_date + e.end_time) at time zone v_tz
      from staff st
      join public.availability_exceptions e on e.staff_id = st.sid and e.org_id = v_service.org_id and e.date = p_date
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
