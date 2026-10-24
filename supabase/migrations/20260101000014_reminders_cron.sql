-- Send booking reminders every 15 minutes. Requires pg_cron, like the hold-expiry job.
select cron.schedule(
  'send-booking-reminders',
  '*/15 * * * *',
  $$select public.send_booking_reminders()$$
);
