-- EliteRadIq: rate limiting for activation attempts.
-- Run after 20260811_production_security.sql.
--
-- Problem fixed: activate_registration() is granted to `anon` (required, since
-- students are not authenticated Supabase users). Without a limit, anyone with
-- the public anon key could script unlimited calls and brute-force valid
-- activation codes, since codes are short alphanumeric strings. This migration
-- adds a sliding-window attempt counter per device_id + IP-independent key and
-- locks an installation out temporarily after repeated failures.

create table if not exists public.activation_attempts (
  device_id text primary key,
  fail_count integer not null default 0,
  first_failed_at bigint not null,
  locked_until bigint
);

alter table public.activation_attempts enable row level security;
revoke all on table public.activation_attempts from anon, authenticated;

-- Window and thresholds: 8 failed attempts per device within 15 minutes
-- triggers a 30 minute lockout. Tune as needed from the Supabase dashboard.
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
  v_attempt record;
  v_window_ms bigint := 15 * 60 * 1000;   -- 15 minutes
  v_lockout_ms bigint := 30 * 60 * 1000;  -- 30 minutes
  v_max_fails integer := 8;
begin
  if length(v_name) < 5 or array_length(regexp_split_to_array(v_name, '\s+'), 1) < 3 then
    raise exception 'يرجى كتابة الاسم الثلاثي الكامل';
  end if;
  if v_code = '' or length(v_code) > 64 then raise exception 'كود التفعيل غير صالح'; end if;
  if v_device = '' or length(v_device) > 128 then raise exception 'معرف الجهاز غير صالح'; end if;

  -- If this installation already has an active registration, return it
  -- rather than creating duplicate records (also short-circuits before the
  -- lockout check so legitimate re-opens of the app never get blocked).
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

  -- Rate limit / lockout check.
  select * into v_attempt from public.activation_attempts where device_id = v_device;

  if v_attempt.device_id is not null then
    if v_attempt.locked_until is not null and v_attempt.locked_until > v_now then
      raise exception 'تم إيقاف المحاولات مؤقتاً لهذا الجهاز بسبب محاولات فاشلة متكررة. يرجى المحاولة لاحقاً.';
    end if;

    -- Reset the counter once the sliding window has elapsed.
    if v_now - v_attempt.first_failed_at > v_window_ms then
      delete from public.activation_attempts where device_id = v_device;
    end if;
  end if;

  if not exists (
    select 1 from public.allowed_codes
    where upper(regexp_replace(code, '\s+', '', 'g')) = v_code
  ) then
    -- Record the failed attempt and lock out if the threshold is exceeded.
    insert into public.activation_attempts(device_id, fail_count, first_failed_at)
    values (v_device, 1, v_now)
    on conflict (device_id) do update
      set fail_count = public.activation_attempts.fail_count + 1
    returning * into v_attempt;

    if v_attempt.fail_count >= v_max_fails then
      update public.activation_attempts
      set locked_until = v_now + v_lockout_ms
      where device_id = v_device;
    end if;

    raise exception 'كود التفعيل غير صحيح';
  end if;

  -- Successful activation: clear any prior failure record for this device.
  delete from public.activation_attempts where device_id = v_device;

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

grant execute on function public.activate_registration(text,text,text) to anon, authenticated;

-- Known remaining limitation: device_id is self-reported by the client, so a
-- scripted attacker can rotate device_id per request to bypass this counter.
-- This migration stops casual/lazy brute-forcing from the shipped app, but it
-- is not a substitute for making activation codes long/high-entropy and,
-- ideally, adding IP-based throttling in front of the Supabase project
-- (e.g. a Cloudflare rule or a Supabase Edge Function proxy) for real defense
-- in depth.
