-- Account deletion (required by both app stores). Bookings, payments and tickets must stay for accounting and
-- refunds, and they reference profiles, so the account is anonymised and disabled instead of the rows being removed.

-- Only direct updates from app roles are guarded; trusted security-definer functions (current_user is their owner)
-- may change the status, e.g. delete_my_account suspending an organization that loses its last owner.
create or replace function public.protect_org_status() returns trigger
language plpgsql as $$
begin
  if new.status is distinct from old.status and auth.uid() is not null and current_user in ('authenticated', 'anon')
     and not public.is_platform_admin() then
    raise exception 'only platform admins can change organization status' using errcode = '42501';
  end if;
  return new;
end $$;

create function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.bookings
     where (customer_id = v_uid or staff_id = v_uid)
       and status in ('held', 'pending_payment', 'confirmed')
       and ends_at > now()
  ) then
    raise exception 'has_active_bookings';
  end if;

  -- An organization that still has upcoming bookings cannot be left without an owner.
  if exists (
    select 1
      from public.org_members m
     where m.user_id = v_uid and m.role = 'owner'
       and not exists (
         select 1 from public.org_members o where o.org_id = m.org_id and o.role = 'owner' and o.user_id <> v_uid)
       and exists (
         select 1 from public.bookings b
          where b.org_id = m.org_id and b.status in ('held', 'pending_payment', 'confirmed') and b.ends_at > now())
  ) then
    raise exception 'org_has_bookings';
  end if;

  -- An organization left without an owner is suspended so it stops taking bookings.
  update public.organizations o set status = 'suspended'
   where exists (select 1 from public.org_members m where m.org_id = o.id and m.user_id = v_uid and m.role = 'owner')
     and not exists (select 1 from public.org_members m where m.org_id = o.id and m.role = 'owner' and m.user_id <> v_uid);

  delete from public.org_members where user_id = v_uid;
  delete from public.staff_services where staff_id = v_uid;
  delete from public.availability_rules where staff_id = v_uid;
  delete from public.availability_exceptions where staff_id = v_uid;
  delete from public.device_tokens where user_id = v_uid;
  delete from public.notifications where user_id = v_uid;

  update public.profiles
     set full_name = 'Deleted user', phone = null, avatar_url = null, is_platform_admin = false
   where id = v_uid;

  -- Disable sign-in and free the email/phone for a future signup. The row stays because profiles references it.
  delete from auth.identities where user_id = v_uid;
  delete from auth.sessions where user_id = v_uid;
  update auth.users
     set email = 'deleted-' || v_uid || '@deleted.invalid',
         phone = null,
         raw_user_meta_data = '{}'::jsonb,
         encrypted_password = null,
         banned_until = 'infinity'
   where id = v_uid;
end $$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
