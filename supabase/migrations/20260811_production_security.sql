-- EliteRadIq production security migration
-- Run this in Supabase SQL Editor after taking a database backup.
-- The mobile app must NOT have direct SELECT/INSERT/UPDATE/DELETE access
-- to activation tables. All operations go through these RPCs.

create extension if not exists pgcrypto;

-- Helper: only authenticated Supabase users with app_metadata.role = admin.
create or replace function public.is_eliteradiq_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin';
$$;

revoke all on function public.is_eliteradiq_admin() from public;
grant execute on function public.is_eliteradiq_admin() to anon, authenticated;

-- Never expose activation tables directly to the mobile client.
alter table if exists public.allowed_codes enable row level security;
alter table if exists public.registered_users enable row level security;

-- Remove legacy table policies so there is no accidental direct access path.
do $$
declare
  p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('allowed_codes', 'registered_users')
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      p.policyname, p.schemaname, p.tablename
    );
  end loop;
end $$;

revoke all on table public.allowed_codes from anon, authenticated;
revoke all on table public.registered_users from anon, authenticated;

-- Admin operations.
create or replace function public.admin_list_codes()
returns table(code text)
language sql
stable
security definer
set search_path = public
as $$
  select ac.code
  from public.allowed_codes ac
  where public.is_eliteradiq_admin()
  order by ac.code;
$$;

create or replace function public.admin_list_users()
returns setof public.registered_users
language sql
stable
security definer
set search_path = public
as $$
  select ru.*
  from public.registered_users ru
  where public.is_eliteradiq_admin()
  order by ru.activated_at desc;
$$;

create or replace function public.admin_add_code(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(regexp_replace(trim(coalesce(p_code, '')), '\s+', '', 'g'));
begin
  if not public.is_eliteradiq_admin() then
    raise exception 'غير مصرح';
  end if;
  if v_code = '' or length(v_code) < 6 or length(v_code) > 64 then
    raise exception 'كود التفعيل غير صالح';
  end if;

  insert into public.allowed_codes(code)
  values (v_code)
  on conflict (code) do nothing;

  return v_code;
end;
$$;

create or replace function public.admin_delete_code(p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_eliteradiq_admin() then
    raise exception 'غير مصرح';
  end if;

  delete from public.allowed_codes
  where upper(code) = upper(regexp_replace(trim(coalesce(p_code, '')), '\s+', '', 'g'));
end;
$$;

create or replace function public.admin_add_user(
  p_full_name text,
  p_code text,
  p_duration_days integer default null
)
returns public.registered_users
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user public.registered_users;
  v_name text := trim(coalesce(p_full_name, ''));
  v_code text := upper(regexp_replace(trim(coalesce(p_code, '')), '\s+', '', 'g'));
  v_now bigint := floor(extract(epoch from clock_timestamp()) * 1000);
  v_exp bigint;
begin
  if not public.is_eliteradiq_admin() then
    raise exception 'غير مصرح';
  end if;
  if length(v_name) < 5 or array_length(regexp_split_to_array(v_name, '\s+'), 1) < 3 then
    raise exception 'الاسم الثلاثي غير صالح';
  end if;
  if v_code = '' then
    raise exception 'كود التفعيل غير صالح';
  end if;

  if p_duration_days is null then
    v_exp := null;
  elsif p_duration_days <= 0 then
    v_exp := v_now - 1;
  else
    v_exp := v_now + (p_duration_days::bigint * 86400000);
  end if;

  insert into public.allowed_codes(code) values (v_code)
  on conflict (code) do nothing;

  insert into public.registered_users(
    id, full_name, activation_code, activated_at, expires_at, device_id
  )
  values (
    gen_random_uuid()::text, v_name, v_code, v_now, v_exp, 'ADMIN_CREATED'
  )
  returning * into v_user;

  return v_user;
end;
$$;

create or replace function public.admin_update_user_duration(
  p_user_id text,
  p_duration_days integer
)
returns public.registered_users
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user public.registered_users;
  v_now bigint := floor(extract(epoch from clock_timestamp()) * 1000);
  v_exp bigint;
begin
  if not public.is_eliteradiq_admin() then
    raise exception 'غير مصرح';
  end if;

  if p_duration_days is null then
    v_exp := null;
  elsif p_duration_days <= 0 then
    v_exp := v_now - 1;
  else
    v_exp := v_now + (p_duration_days::bigint * 86400000);
  end if;

  update public.registered_users
  set expires_at = v_exp
  where id = p_user_id
  returning * into v_user;

  if v_user.id is null then raise exception 'المستخدم غير موجود'; end if;
  return v_user;
end;
$$;

create or replace function public.admin_delete_user(p_user_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_eliteradiq_admin() then
    raise exception 'غير مصرح';
  end if;
  delete from public.registered_users where id = p_user_id;
end;
$$;

-- Student activation: no direct table access is needed.
create or replace function public.activate_registration(
  p_full_name text,
  p_code text,
  p_device_id text
)
returns setof public.registered_users
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user public.registered_users;
  v_name text := trim(coalesce(p_full_name, ''));
  v_code text := upper(regexp_replace(trim(coalesce(p_code, '')), '\s+', '', 'g'));
  v_device text := trim(coalesce(p_device_id, ''));
  v_now bigint := floor(extract(epoch from clock_timestamp()) * 1000);
  v_exp bigint := v_now + (365::bigint * 86400000);
begin
  if length(v_name) < 5 or array_length(regexp_split_to_array(v_name, '\s+'), 1) < 3 then
    raise exception 'يرجى كتابة الاسم الثلاثي الكامل';
  end if;
  if v_code = '' or length(v_code) > 64 then raise exception 'كود التفعيل غير صالح'; end if;
  if v_device = '' or length(v_device) > 128 then raise exception 'معرف الجهاز غير صالح'; end if;

  -- If this installation already has an active registration, return it
  -- rather than creating duplicate records.
  select *
  into v_user
  from public.registered_users
  where device_id = v_device
    and (expires_at is null or expires_at = 0 or expires_at > v_now)
  order by activated_at desc
  limit 1;

  if v_user.id is not null then
    return next v_user;
    return;
  end if;

  if not exists (
    select 1 from public.allowed_codes
    where upper(regexp_replace(code, '\s+', '', 'g')) = v_code
  ) then
    raise exception 'كود التفعيل غير صحيح';
  end if;

  insert into public.registered_users(
    id, full_name, activation_code, activated_at, expires_at, device_id
  )
  values (
    gen_random_uuid()::text, v_name, v_code, v_now, v_exp, v_device
  )
  returning * into v_user;

  return next v_user;
end;
$$;

create or replace function public.get_my_registration(
  p_user_id text,
  p_device_id text
)
returns setof public.registered_users
language sql
stable
security definer
set search_path = public
as $$
  select ru.*
  from public.registered_users ru
  where ru.id = p_user_id
    and ru.device_id = p_device_id
    and (
      ru.expires_at is null
      or ru.expires_at = 0
      or ru.expires_at > floor(extract(epoch from clock_timestamp()) * 1000)
    );
$$;

create or replace function public.deactivate_registration(
  p_user_id text,
  p_device_id text
)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.registered_users
  where id = p_user_id and device_id = p_device_id;
$$;

-- Explicit RPC grants.
revoke all on function public.admin_list_codes() from public;
revoke all on function public.admin_list_users() from public;
revoke all on function public.admin_add_code(text) from public;
revoke all on function public.admin_delete_code(text) from public;
revoke all on function public.admin_add_user(text,text,integer) from public;
revoke all on function public.admin_update_user_duration(text,integer) from public;
revoke all on function public.admin_delete_user(text) from public;
revoke all on function public.activate_registration(text,text,text) from public;
revoke all on function public.get_my_registration(text,text) from public;
revoke all on function public.deactivate_registration(text,text) from public;

grant execute on function public.admin_list_codes() to authenticated;
grant execute on function public.admin_list_users() to authenticated;
grant execute on function public.admin_add_code(text) to authenticated;
grant execute on function public.admin_delete_code(text) to authenticated;
grant execute on function public.admin_add_user(text,text,integer) to authenticated;
grant execute on function public.admin_update_user_duration(text,integer) to authenticated;
grant execute on function public.admin_delete_user(text) to authenticated;

grant execute on function public.activate_registration(text,text,text) to anon, authenticated;
grant execute on function public.get_my_registration(text,text) to anon, authenticated;
grant execute on function public.deactivate_registration(text,text) to anon, authenticated;

-- Recommended: keep service-role-only maintenance outside the mobile app.
