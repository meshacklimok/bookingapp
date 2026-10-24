-- Notification inbox: booking confirmations and reminders ---------------------------------------------------------------
-- Rows are created by the database (triggers and cron functions), never by the app. `data.route` is an in-app path the
-- inbox opens on tap. Push delivery would read the same rows (device_tokens); it is not wired up yet.

-- one row per (user, event): reminders and confirmations can run twice without duplicating
alter table public.notifications add column dedupe_key text;
create unique index notifications_dedupe_idx on public.notifications (user_id, dedupe_key) where dedupe_key is not null;
create index notifications_unread_idx on public.notifications (user_id) where read_at is null;

-- The existing policy lets owners update any column of their rows. They may only mark them read.
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;
create policy notifications_delete on public.notifications for delete to authenticated using (user_id = auth.uid());

alter publication supabase_realtime add table public.notifications;

create function public.mark_notifications_read(p_ids uuid[] default null) returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  update public.notifications
     set read_at = now()
   where user_id = auth.uid() and read_at is null and (p_ids is null or id = any (p_ids));
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.mark_notifications_read(uuid[]) from public, anon;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated;

-- A booking becoming confirmed tells the customer, and tells the organization it has a new booking.
create function public.notify_booking_confirmed() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
begin
  select title into v_title from public.services where id = new.service_id;
  insert into public.notifications (user_id, title, body, data, dedupe_key)
  values (new.customer_id, 'Booking confirmed',
          v_title || ' on ' || to_char(new.starts_at at time zone 'Africa/Nairobi', 'Dy DD Mon, HH24:MI') || '.',
          jsonb_build_object('booking_id', new.id, 'route', '/bookings'), 'confirmed:' || new.id)
  on conflict do nothing;
  insert into public.notifications (user_id, title, body, data, dedupe_key)
  select m.user_id, 'New booking', v_title || ' on ' || to_char(new.starts_at at time zone 'Africa/Nairobi', 'Dy DD Mon, HH24:MI') || '.',
         jsonb_build_object('booking_id', new.id, 'route', '/org/' || new.org_id), 'org_confirmed:' || new.id
    from public.org_members m
   where m.org_id = new.org_id and m.role in ('owner', 'admin')
  on conflict do nothing;
  return new;
end $$;
create trigger on_booking_confirmed
  after update of status on public.bookings
  for each row
  when (old.status is distinct from 'confirmed' and new.status = 'confirmed')
  execute function public.notify_booking_confirmed();

-- Reminds customers about bookings starting within the next 24 hours. Safe to run as often as you like.
create function public.send_booking_reminders() returns integer
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
   where b.status = 'confirmed' and b.starts_at > now() and b.starts_at <= now() + interval '24 hours'
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_booking_reminders() from public, anon, authenticated;
