-- Core tables. All money is stored as integer cents (KES).

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  phone text,
  avatar_url text,
  is_platform_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  description text,
  logo_url text,
  category text,
  status public.org_status not null default 'pending',
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

create table public.org_members (
  org_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role public.org_role not null default 'staff',
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);
create index org_members_user_idx on public.org_members (user_id);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  title text not null,
  description text,
  category text,
  booking_mode public.booking_mode not null default 'appointment',
  price_cents integer not null default 0 check (price_cents >= 0),
  currency text not null default 'KES',
  duration_min integer not null default 60 check (duration_min > 0),
  buffer_min integer not null default 0 check (buffer_min >= 0),
  capacity integer not null default 1 check (capacity > 0),
  location text,
  images text[] not null default '{}',
  event_starts_at timestamptz,
  event_ends_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index services_org_idx on public.services (org_id);
create index services_active_idx on public.services (is_active, category);

create table public.staff_services (
  staff_id uuid not null references public.profiles (id) on delete cascade,
  service_id uuid not null references public.services (id) on delete cascade,
  primary key (staff_id, service_id)
);

-- weekday follows Postgres extract(dow): 0 = Sunday ... 6 = Saturday. Times are Africa/Nairobi.
create table public.availability_rules (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  staff_id uuid not null references public.profiles (id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),
  start_time time not null,
  end_time time not null,
  check (end_time > start_time)
);
create index availability_rules_staff_idx on public.availability_rules (staff_id, weekday);

-- A row for a date overrides the weekly rules for that staff member on that date.
create table public.availability_exceptions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  staff_id uuid not null references public.profiles (id) on delete cascade,
  date date not null,
  is_closed boolean not null default true,
  start_time time,
  end_time time,
  unique (staff_id, date),
  check (is_closed or (start_time is not null and end_time is not null and end_time > start_time))
);

create table public.ticket_tiers (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services (id) on delete cascade,
  name text not null,
  price_cents integer not null default 0 check (price_cents >= 0),
  quantity integer not null check (quantity >= 0),
  sold integer not null default 0 check (sold >= 0 and sold <= quantity),
  sales_start timestamptz,
  sales_end timestamptz
);
create index ticket_tiers_service_idx on public.ticket_tiers (service_id);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id),
  service_id uuid not null references public.services (id),
  org_id uuid not null references public.organizations (id),
  staff_id uuid references public.profiles (id),
  tier_id uuid references public.ticket_tiers (id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  quantity integer not null default 1 check (quantity > 0),
  status public.booking_status not null default 'held',
  expires_at timestamptz,
  total_cents bigint not null check (total_cents >= 0),
  commission_pct numeric(5, 2),
  commission_cents bigint,
  org_earnings_cents bigint,
  -- staff id for appointments, service id for resources, null for events
  exclusive_key uuid,
  time_range tstzrange generated always as (tstzrange(starts_at, ends_at, '[)')) stored,
  notes text,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  constraint bookings_no_overlap exclude using gist (exclusive_key with =, time_range with &&)
    where (exclusive_key is not null and status in ('held', 'pending_payment', 'confirmed'))
);
create index bookings_customer_idx on public.bookings (customer_id, starts_at desc);
create index bookings_org_idx on public.bookings (org_id, starts_at desc);
create index bookings_expiry_idx on public.bookings (expires_at) where status in ('held', 'pending_payment');

create table public.tickets (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id) on delete cascade,
  org_id uuid not null references public.organizations (id),
  customer_id uuid not null references public.profiles (id),
  qr_token text not null unique
    default replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
  status public.ticket_status not null default 'valid',
  checked_in_at timestamptz,
  checked_in_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);
create index tickets_booking_idx on public.tickets (booking_id);
create index tickets_customer_idx on public.tickets (customer_id);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id),
  customer_id uuid not null references public.profiles (id),
  org_id uuid not null references public.organizations (id),
  provider public.payment_provider not null,
  -- M-Pesa CheckoutRequestID, or the payment id sent to Paystack as the reference
  reference text unique,
  amount_cents bigint not null check (amount_cents >= 0),
  phone text,
  status public.payment_status not null default 'pending',
  provider_receipt text,
  raw_payload jsonb,
  -- set when money arrived but the booking could no longer be confirmed (needs manual refund)
  needs_review boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index payments_booking_idx on public.payments (booking_id);

create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments (id),
  amount_cents bigint not null check (amount_cents > 0),
  reason text,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

create table public.commission_settings (
  id uuid primary key default gen_random_uuid(),
  scope public.commission_scope not null,
  scope_id uuid,
  pct numeric(5, 2) not null check (pct between 0 and 100),
  check ((scope = 'platform') = (scope_id is null))
);
create unique index commission_settings_scope_idx
  on public.commission_settings (scope, coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- Platform default commission. Change this value to set your own rate.
insert into public.commission_settings (scope, scope_id, pct) values ('platform', null, 10.00);

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  token text not null unique,
  platform text,
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  body text,
  data jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

-- Triggers

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (new.id, new.raw_user_meta_data ->> 'full_name', new.phone)
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.add_org_owner() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.created_by is not null then
    insert into public.org_members (org_id, user_id, role) values (new.id, new.created_by, 'owner');
  end if;
  return new;
end $$;

create trigger on_organization_created
  after insert on public.organizations
  for each row execute function public.add_org_owner();

-- Release ticket inventory when a booking that held it is cancelled.
create function public.release_tier_inventory() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.tier_id is not null then
    update public.ticket_tiers set sold = greatest(sold - old.quantity, 0) where id = new.tier_id;
  end if;
  return new;
end $$;

create trigger on_booking_cancelled
  after update of status on public.bookings
  for each row
  when (old.status in ('held', 'pending_payment', 'confirmed') and new.status = 'cancelled')
  execute function public.release_tier_inventory();
