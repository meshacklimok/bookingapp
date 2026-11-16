-- SMS delivery: booking confirmations and reminders are also texted to the customer (send-sms Edge Function) ----------
-- Only these two kinds are texted, since every SMS costs money. Everything else stays push and in-app.

alter table public.profiles add column sms_enabled boolean not null default true;
alter table public.notifications add column sms_at timestamptz;
create index notifications_unsmsed_idx on public.notifications (created_at)
  where sms_at is null and (dedupe_key like 'confirmed:%' or dedupe_key like 'reminder:%');

-- Takes the next batch of texts to send and marks them sent in the same statement, so two overlapping runs never text
-- the same thing twice. Rows for users without a phone number or who opted out are marked without being returned, and
-- anything older than two hours is dropped (a reminder that late is noise).
create function public.claim_unsmsed_notifications(p_limit integer default 50)
returns table (id uuid, phone text, title text, body text)
language plpgsql security definer set search_path = public as $$
begin
  update public.notifications n set sms_at = now()
   where n.sms_at is null
     and (n.dedupe_key like 'confirmed:%' or n.dedupe_key like 'reminder:%')
     and (n.created_at <= now() - interval '2 hours'
          or not exists (select 1 from public.profiles p
                          where p.id = n.user_id and p.phone is not null and p.sms_enabled));
  return query
  with next as (
    select n.id from public.notifications n
     where n.sms_at is null and (n.dedupe_key like 'confirmed:%' or n.dedupe_key like 'reminder:%')
     order by n.created_at
     limit p_limit
     for update skip locked
  )
  update public.notifications n set sms_at = now()
    from next, public.profiles p
   where n.id = next.id and p.id = n.user_id
  returning n.id, p.phone, n.title, n.body;
end $$;
revoke execute on function public.claim_unsmsed_notifications(integer) from public, anon, authenticated;
