-- Push delivery: every notification row is also sent to the user's devices (send-push Edge Function) -------------------

alter table public.notifications add column pushed_at timestamptz;
create index notifications_unpushed_idx on public.notifications (created_at) where pushed_at is null;

-- Takes the next batch of notifications to push and marks them pushed in the same statement, so two overlapping runs
-- never send the same one twice. Anything older than a day is dropped from the queue without being sent.
create function public.claim_unpushed_notifications(p_limit integer default 50)
returns table (id uuid, user_id uuid, title text, body text, data jsonb)
language plpgsql security definer set search_path = public as $$
begin
  update public.notifications set pushed_at = now()
   where pushed_at is null and created_at <= now() - interval '1 day';
  return query
  with next as (
    select n.id from public.notifications n
     where n.pushed_at is null
     order by n.created_at
     limit p_limit
     for update skip locked
  )
  update public.notifications n set pushed_at = now()
    from next
   where n.id = next.id
  returning n.id, n.user_id, n.title, n.body, n.data;
end $$;
revoke execute on function public.claim_unpushed_notifications(integer) from public, anon, authenticated;

-- A device token belongs to whoever signed in last. A plain upsert from the app would fail row-level security when the
-- same phone was used by another account before.
create function public.register_device_token(p_token text, p_platform text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_token is null or length(p_token) = 0 then raise exception 'token required'; end if;
  insert into public.device_tokens (user_id, token, platform)
  values (auth.uid(), p_token, p_platform)
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform;
end $$;
revoke execute on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;
