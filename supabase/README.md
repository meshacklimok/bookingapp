# Supabase backend

## Setup
1. Create a project at supabase.com. Note the project URL and anon key.
2. Install the Supabase CLI, then from the repo root:
   ```
   supabase link --project-ref <your-project-ref>
   supabase db push                 # runs supabase/migrations/*
   ```
   Enable the `pg_cron` extension first (Dashboard, Database, Extensions) or the last migration fails.
3. Auth redirect: Dashboard, Authentication, URL Configuration, add `com.example.bookingapp://auth-callback`
   to Redirect URLs. Sign-up confirmation and password reset emails open the app through it.
   If you change the app id, update it in `lib/core/config/env.dart`, `AndroidManifest.xml` and `Info.plist` too.
   For Flutter Web, also add the web app's URL with a wildcard (e.g. `http://localhost:3000/**`).
   "Continue with Google": in Google Cloud Console create an OAuth client (type Web application) with
   `https://<ref>.supabase.co/auth/v1/callback` as an authorized redirect URI, then paste its client id and
   secret into Dashboard, Authentication, Sign In / Providers, Google. The app opens Google in the browser and
   returns through the same redirect URL, so no Android or iOS client ids are needed.
4. Optional demo data: run `supabase/seed.sql` in the SQL editor.
5. Edge Function secrets:
   ```
   cp supabase/.env.example supabase/.env     # then fill it in
   supabase secrets set --env-file supabase/.env
   supabase functions deploy create-payment
   supabase functions deploy mpesa-callback
   supabase functions deploy paystack-webhook
   supabase functions deploy mpesa-reconcile
   supabase functions deploy send-push
   supabase functions deploy send-sms
   supabase functions deploy process-refund
   ```
6. Point the provider callbacks at your functions:
   - Paystack dashboard, Webhook URL: `https://<ref>.supabase.co/functions/v1/paystack-webhook`
   - M-Pesa: the callback URL is built automatically by `create-payment`.
7. Backup for lost M-Pesa callbacks: enable `pg_net` too, then store the project URL and `CRON_SECRET` in Vault
   (the commands are at the top of `migrations/..._mpesa_reconcile_cron.sql`). pg_cron then calls `mpesa-reconcile`
   every minute, which asks Daraja about payments still pending after 2 minutes.
8. Push notifications: create a Firebase project, put its service-account JSON key in `FCM_SERVICE_ACCOUNT`, and
   deploy `send-push`. The same Vault secrets let pg_cron call it every minute. It sends each new notification to the
   user's devices. The app registers a device with `rpc('register_device_token', {p_token, p_platform})` once it has
   an FCM token (the Flutter side still needs `firebase_messaging` and the Firebase config files).
9. SMS: create an Africa's Talking account, set `AT_USERNAME` (`sandbox` to try it), `AT_API_KEY` and optionally
   `AT_SENDER_ID`, and deploy `send-sms`. pg_cron calls it every minute with the same Vault secrets. It texts booking
   confirmations and reminders to customers with a phone number on their profile (`profiles.sms_enabled` is the opt-out).

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

## Tests
`supabase/tests/run.sh` applies the migrations to a scratch Postgres (no Supabase needed, `pg_cron` is skipped) and checks
double-booking, holds, inventory, payments, commission, check-in and RLS:
```
PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres supabase/tests/run.sh
```
It drops and recreates a database named `booking_test`, so point it at a throwaway server.

The payment callbacks (`mpesa-callback`, `paystack-webhook`) keep their logic in `handler.ts` and are tested with a fake
database client, no network or Supabase needed. Requires [Deno](https://deno.com):
```
deno test --allow-env supabase/functions/
```
