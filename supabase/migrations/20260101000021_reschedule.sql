-- Rescheduling ------------------------------------------------------------------------------------------------------
-- A customer can move a paid appointment or space booking to another free slot for as long as a cancellation would still
-- be refunded in full (the service's free-cancellation window). The price and payment stay as they are, the ticket
-- stays valid, and the old slot is released in the same statement.
create function public.reschedule_booking(p_booking_id uuid, p_new_start timestamptz, p_staff_id uuid default null)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  b public.bookings%rowtype;
  s public.services%rowtype;
  v_staff uuid;
  v_title text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into b from public.bookings where id = p_booking_id and customer_id = v_uid for update;
  if not found or b.status <> 'confirmed' or b.starts_at <= now() then
    raise exception 'cannot_reschedule';
  end if;
  select * into s from public.services where id = b.service_id;
  if s.booking_mode not in ('appointment', 'resource') then
    raise exception 'cannot_reschedule';
  end if;
  if b.starts_at - make_interval(hours => s.free_cancel_hours) < now() then
    raise exception 'reschedule_window_closed';
  end if;
  if exists (select 1 from public.tickets t where t.booking_id = b.id and t.status = 'used') then
    raise exception 'ticket_used';
  end if;

  if s.booking_mode = 'appointment' then
    v_staff := coalesce(p_staff_id, b.staff_id);
    if not exists (
      select 1 from public.get_available_slots(s.id, (p_new_start at time zone 'Africa/Nairobi')::date, v_staff) g
       where g.slot_start = p_new_start
    ) then
      raise exception 'slot_unavailable';
    end if;
  else
    v_staff := null;
    if not exists (
      select 1 from public.get_resource_slots(s.id, (p_new_start at time zone 'Africa/Nairobi')::date) g
       where g.slot_start = p_new_start
    ) then
      raise exception 'slot_unavailable';
    end if;
  end if;

  begin
    update public.bookings
       set starts_at = p_new_start,
           ends_at = p_new_start + make_interval(mins => s.duration_min + s.buffer_min),
           staff_id = v_staff,
           exclusive_key = coalesce(v_staff, s.id)
     where id = b.id
    returning * into b;
  exception when exclusion_violation then
    raise exception 'slot_unavailable';
  end;

  -- the reminder for the new time has not been sent yet
  delete from public.notifications where dedupe_key = 'reminder:' || b.id;

  v_title := s.title;
  insert into public.notifications (user_id, title, body, data)
  select m.user_id, 'Booking rescheduled',
         v_title || ' moved to ' || to_char(b.starts_at at time zone 'Africa/Nairobi', 'Dy DD Mon, HH24:MI') || '.',
         jsonb_build_object('booking_id', b.id, 'route', '/org/' || b.org_id)
    from public.org_members m
   where m.org_id = b.org_id and m.role in ('owner', 'admin');
  return b;
end $$;
revoke execute on function public.reschedule_booking(uuid, timestamptz, uuid) from public, anon;
grant execute on function public.reschedule_booking(uuid, timestamptz, uuid) to authenticated;
