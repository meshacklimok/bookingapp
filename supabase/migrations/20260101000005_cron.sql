-- Release expired holds every minute so unpaid bookings free their slots and ticket inventory.
-- Requires the pg_cron extension (Supabase Dashboard > Database > Extensions > pg_cron).

create extension if not exists pg_cron;

select cron.schedule(
  'release-expired-holds',
  '* * * * *',
  $$select public.release_expired_holds()$$
);
