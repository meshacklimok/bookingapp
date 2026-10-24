-- Staff directory for the slot picker, storage buckets, and owner-only owner changes.

-- Customers cannot read other users' profiles, so expose just the public fields of a service's staff.
create function public.get_service_staff(p_service_id uuid)
returns table (staff_id uuid, full_name text, avatar_url text)
language sql stable security definer set search_path = public as $$
  select p.id, p.full_name, p.avatar_url
    from public.staff_services ss
    join public.profiles p on p.id = ss.staff_id
    join public.services s on s.id = ss.service_id
    join public.organizations o on o.id = s.org_id
   where ss.service_id = p_service_id and s.is_active and o.status = 'approved'
   order by p.full_name
$$;
revoke execute on function public.get_service_staff(uuid) from public;
grant execute on function public.get_service_staff(uuid) to anon, authenticated;

-- Only owners may create, change or remove owner rows; admins manage admins and staff.
drop policy org_members_write on public.org_members;
create policy org_members_write on public.org_members for all to authenticated
  using (
    public.is_org_member(org_id, array['owner']::public.org_role[])
    or (public.is_org_member(org_id, array['admin']::public.org_role[]) and role <> 'owner')
  )
  with check (
    public.is_org_member(org_id, array['owner']::public.org_role[])
    or (public.is_org_member(org_id, array['admin']::public.org_role[]) and role <> 'owner')
  );

-- Storage: avatars live under <user id>/..., organization images under <org id>/...
insert into storage.buckets (id, name, public) values
  ('avatars', 'avatars', true),
  ('org-assets', 'org-assets', true)
on conflict (id) do nothing;

create policy avatars_write on storage.objects for all to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy org_assets_write on storage.objects for all to authenticated
  using (
    bucket_id = 'org-assets'
    and public.is_org_member(((storage.foldername(name))[1])::uuid, array['owner', 'admin']::public.org_role[])
  )
  with check (
    bucket_id = 'org-assets'
    and public.is_org_member(((storage.foldername(name))[1])::uuid, array['owner', 'admin']::public.org_role[])
  );
