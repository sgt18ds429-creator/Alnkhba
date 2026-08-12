-- EliteRadIq baseline schema.
-- Safe to apply to a new project; existing deployments are left intact.

create extension if not exists pgcrypto;

revoke create on schema public from public, anon, authenticated;
grant usage on schema public to anon, authenticated;

create table if not exists public.allowed_codes (
  code text primary key
);

create table if not exists public.registered_users (
  id text primary key default gen_random_uuid()::text,
  full_name text not null,
  activation_code text not null,
  activated_at bigint not null,
  expires_at bigint,
  device_id text not null
);

create index if not exists registered_users_device_id_idx
  on public.registered_users(device_id);

create index if not exists registered_users_activation_code_idx
  on public.registered_users(activation_code);

alter table public.allowed_codes enable row level security;
alter table public.registered_users enable row level security;

-- No table grants are needed by the mobile client. Later migrations expose
-- narrowly scoped SECURITY DEFINER functions instead.
revoke all on table public.allowed_codes from anon, authenticated;
revoke all on table public.registered_users from anon, authenticated;
