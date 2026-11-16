-- Every minute, ask Daraja about M-Pesa payments whose callback never arrived (mpesa-reconcile Edge Function).
-- Requires pg_cron and pg_net, and two Vault secrets created once in the SQL editor:
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<the CRON_SECRET Edge Function secret>', 'cron_secret');
create extension if not exists pg_net;

select cron.schedule(
  'mpesa-reconcile',
  '* * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/mpesa-reconcile',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := '{}'::jsonb
  )
  $$
);
