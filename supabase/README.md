# Supabase backend

## Setup
1. Create a project at supabase.com. Note the project URL and anon key.
2. Install the Supabase CLI, then from the repo root:
   ```
   supabase link --project-ref <your-project-ref>
   supabase db push                 # runs supabase/migrations/*
   ```
   Enable the `pg_cron` extension first (Dashboard, Database, Extensions) or the last migration fails.
3. Optional demo data: run `supabase/seed.sql` in the SQL editor.
4. Edge Function secrets:
   ```
   copy supabase\.env.example supabase\.env     # then fill it in
   supabase secrets set --env-file supabase/.env
   supabase functions deploy create-payment
   supabase functions deploy mpesa-callback
   supabase functions deploy paystack-webhook
   ```
5. Point the provider callbacks at your functions:
   - Paystack dashboard, Webhook URL: `https://<ref>.supabase.co/functions/v1/paystack-webhook`
   - M-Pesa: the callback URL is built automatically by `create-payment`.

## Make yourself platform admin
After signing up in the app, run in the SQL editor:
```sql
update public.profiles set is_platform_admin = true where id = '<your auth user id>';
```
Platform admins can approve organizations (`update organizations set status = 'approved'`) and edit `commission_settings`.

## Set commission
```sql
-- platform default
update public.commission_settings set pct = 8 where scope = 'platform';
-- one organization or one service
insert into public.commission_settings (scope, scope_id, pct) values ('org', '<org id>', 5);
insert into public.commission_settings (scope, scope_id, pct) values ('service', '<service id>', 3);
```

## Try an appointment service
Appointments need staff. With a signed-up user `<staff id>` and an approved org `<org id>`:
```sql
insert into public.org_members (org_id, user_id, role) values ('<org id>', '<staff id>', 'owner');
insert into public.services (id, org_id, title, booking_mode, price_cents, duration_min, buffer_min, category)
  values ('33333333-3333-3333-3333-333333333333', '<org id>', 'Haircut', 'appointment', 80000, 45, 15, 'Beauty');
insert into public.staff_services values ('<staff id>', '33333333-3333-3333-3333-333333333333');
-- Monday to Friday, 09:00 to 17:00 (Africa/Nairobi); weekday 0 = Sunday
insert into public.availability_rules (org_id, staff_id, weekday, start_time, end_time)
  select '<org id>', '<staff id>', d, '09:00', '17:00' from generate_series(1, 5) d;
```

## Notes
- Money is integer cents. M-Pesa charges whole shillings, so amounts are rounded up to the next shilling for the STK push.
- Bookings, tickets and payments cannot be written from the app. They change only through the functions in `20260101000003_functions.sql` and the Edge Functions.
