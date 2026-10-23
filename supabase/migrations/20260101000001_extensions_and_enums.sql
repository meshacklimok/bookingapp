-- Extensions and enum types

create extension if not exists btree_gist;

create type public.booking_mode as enum ('appointment', 'event', 'resource');
create type public.booking_status as enum ('held', 'pending_payment', 'confirmed', 'cancelled', 'completed', 'no_show');
create type public.ticket_status as enum ('valid', 'used', 'void');
create type public.payment_provider as enum ('mpesa', 'paystack');
create type public.payment_status as enum ('pending', 'success', 'failed', 'refunded');
create type public.org_role as enum ('owner', 'admin', 'staff');
create type public.org_status as enum ('pending', 'approved', 'suspended');
create type public.commission_scope as enum ('platform', 'org', 'service');
