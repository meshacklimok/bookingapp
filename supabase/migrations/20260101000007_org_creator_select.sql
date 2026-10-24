-- A creator must be able to read back the organization they just inserted. The owner row is added by an
-- after-insert trigger, so `insert ... returning` is evaluated before is_org_member() can be true.
drop policy organizations_select on public.organizations;
create policy organizations_select on public.organizations for select
  using (status = 'approved' or created_by = auth.uid() or public.is_org_member(id) or public.is_platform_admin());
