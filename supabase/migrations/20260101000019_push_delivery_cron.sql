-- Calls the send-push Edge Function every minute. Requires pg_cron, pg_net and the two Vault secrets described in
-- ..._mpesa_reconcile_cron.sql (project_url, cron_secret).
create extension if not exists pg_net;

select cron.schedule(
  'send-push',
  '* * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := '{}'::jsonb
  )
  $$
);
