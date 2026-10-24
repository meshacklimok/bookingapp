-- Guards for organizations managing their own services.

-- An event cannot end before it starts.
alter table public.services
  add constraint services_event_window_check
  check (event_ends_at is null or event_starts_at is null or event_ends_at > event_starts_at);

-- The "from" price shown for an event is its cheapest ticket tier, kept in sync here so no client can drift.
create function public.sync_event_price() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_service uuid := coalesce(new.service_id, old.service_id);
begin
  update public.services s
     set price_cents = coalesce((select min(t.price_cents) from public.ticket_tiers t where t.service_id = s.id), 0)
   where s.id = v_service and s.booking_mode = 'event';
  return null;
end $$;

create trigger ticket_tiers_sync_event_price
  after insert or update of price_cents or delete on public.ticket_tiers
  for each row execute function public.sync_event_price();

-- Switching a service between appointment and event after people booked it would corrupt those bookings.
create function public.protect_service_mode() returns trigger
language plpgsql as $$
begin
  if new.booking_mode is distinct from old.booking_mode
     and exists (select 1 from public.bookings b where b.service_id = old.id) then
    raise exception 'service_has_bookings' using errcode = '23514';
  end if;
  return new;
end $$;

create trigger services_protect_mode
  before update on public.services
  for each row execute function public.protect_service_mode();
