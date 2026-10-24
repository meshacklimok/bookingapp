-- Automatic refunds. The process-refund Edge Function claims a pending refund (-> processing), asks the provider to
-- pay it back, and the Paystack webhook settles it. resolve_refund (manual, platform admin) keeps working for
-- M-Pesa and for retries.

alter table public.refunds drop constraint refunds_status_check;
alter table public.refunds
  add column last_error text,
  add constraint refunds_status_check check (status in ('pending', 'processing', 'processed', 'failed'));

-- Settles a refund that is pending or being processed. No auth check: only the service role (Edge Functions) and
-- resolve_refund call it.
create function public.finish_refund(p_refund_id uuid, p_status text, p_provider_ref text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.refunds%rowtype;
  v_pay public.payments%rowtype;
begin
  if p_status not in ('processed', 'failed') then
    raise exception 'invalid_status';
  end if;
  select * into r from public.refunds where id = p_refund_id for update;
  if not found or r.status not in ('pending', 'processing') then
    raise exception 'refund_not_pending';
  end if;
  update public.refunds
     set status = p_status,
         provider_ref = coalesce(p_provider_ref, provider_ref),
         processed_at = now(),
         last_error = null
   where id = r.id;
  if p_status = 'processed' then
    select * into v_pay from public.payments where id = r.payment_id for update;
    if (select coalesce(sum(amount_cents), 0) from public.refunds where payment_id = v_pay.id and status = 'processed') >= v_pay.amount_cents then
      update public.payments set status = 'refunded', updated_at = now() where id = v_pay.id;
    end if;
    insert into public.notifications (user_id, title, body, data)
    values (v_pay.customer_id, 'Refund sent', 'Your refund has been paid out.', jsonb_build_object('refund_id', r.id, 'route', '/bookings'));
  end if;
end $$;
revoke execute on function public.finish_refund(uuid, text, text) from public, anon, authenticated;
grant execute on function public.finish_refund(uuid, text, text) to service_role;

-- Same behaviour as before for admins, but also able to settle a stuck `processing` refund.
create or replace function public.resolve_refund(p_refund_id uuid, p_status text, p_provider_ref text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  perform public.finish_refund(p_refund_id, p_status, p_provider_ref);
end $$;
revoke execute on function public.resolve_refund(uuid, text, text) from public, anon;
grant execute on function public.resolve_refund(uuid, text, text) to authenticated;
