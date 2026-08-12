-- EliteRadIq release hardening (v2 activation protocol)
-- Apply after 20260811_production_security.sql and
-- 20260812_activation_rate_limit.sql.
--
-- Fixes:
--   * failed-attempt counters now commit (invalid codes return JSON instead of
--     raising an exception that rolls the transaction back);
--   * activation codes have an atomic use limit and configurable duration;
--   * the backend can validate a high-entropy, revocable activation token;
--   * account deletion is idempotent and reports a structured result.

create extension if not exists pgcrypto;

alter table public.allowed_codes
  add column if not exists duration_days integer not null default 365,
  add column if not exists max_uses integer not null default 1,
  add column if not exists used_count integer not null default 0,
  add column if not exists active boolean not null default true,
  add column if not exists created_at timestamptz not null default now();

alter table public.registered_users
  add column if not exists access_token_hash text,
  add column if not exists pending boolean not null default false;

update public.registered_users
set pending = true
where device_id = 'ADMIN_CREATED';

create table if not exists public.activation_attempts (
  device_id text primary key,
  fail_count integer not null default 0,
  first_failed_at bigint not null,
  locked_until bigint
);

alter table public.activation_attempts enable row level security;
revoke all on table public.activation_attempts from anon, authenticated;

create table if not exists public.ai_safety_reports (
  id uuid primary key default gen_random_uuid(),
  registration_id text not null,
  message_id text not null,
  message_text text not null,
  reason text not null,
  client_reported_at timestamptz,
  created_at timestamptz not null default now(),
  status text not null default 'open'
);

create index if not exists ai_safety_reports_created_at_idx
  on public.ai_safety_reports(created_at);

create index if not exists ai_safety_reports_registration_id_idx
  on public.ai_safety_reports(registration_id);

alter table public.ai_safety_reports enable row level security;
revoke all on table public.ai_safety_reports from anon, authenticated;
grant select, insert, update, delete on table public.ai_safety_reports to service_role;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'allowed_codes_duration_days_check'
      and conrelid = 'public.allowed_codes'::regclass
  ) then
    alter table public.allowed_codes
      add constraint allowed_codes_duration_days_check
      check (duration_days between 0 and 3650);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'allowed_codes_max_uses_check'
      and conrelid = 'public.allowed_codes'::regclass
  ) then
    alter table public.allowed_codes
      add constraint allowed_codes_max_uses_check
      check (max_uses between 1 and 10000);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'allowed_codes_used_count_check'
      and conrelid = 'public.allowed_codes'::regclass
  ) then
    alter table public.allowed_codes
      add constraint allowed_codes_used_count_check
      check (used_count >= 0);
  end if;
end $$;

create or replace function public.activate_registration_v2(
  p_full_name text,
  p_code text,
  p_device_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user public.registered_users;
  v_name text := trim(coalesce(p_full_name, ''));
  v_code text := upper(regexp_replace(trim(coalesce(p_code, '')), '\s+', '', 'g'));
  v_device text := trim(coalesce(p_device_id, ''));
  v_now bigint := floor(extract(epoch from clock_timestamp()) * 1000);
  v_window_ms constant bigint := 15 * 60 * 1000;
  v_lockout_ms constant bigint := 30 * 60 * 1000;
  v_max_fails constant integer := 8;
  v_attempt public.activation_attempts%rowtype;
  v_code_row public.allowed_codes%rowtype;
  v_token text;
  v_exp bigint;
begin
  if length(v_name) < 5
     or coalesce(array_length(regexp_split_to_array(v_name, '\s+'), 1), 0) < 3
     or length(v_name) > 160 then
    return jsonb_build_object(
      'ok', false,
      'message', 'يرجى كتابة الاسم الثلاثي الكامل'
    );
  end if;
  if v_code = '' or length(v_code) < 6 or length(v_code) > 64 then
    return jsonb_build_object('ok', false, 'message', 'كود التفعيل غير صالح');
  end if;
  if v_device = '' or length(v_device) < 24 or length(v_device) > 128 then
    return jsonb_build_object('ok', false, 'message', 'معرف التثبيت غير صالح');
  end if;

  -- Serialize activations from the same installation to prevent duplicates.
  perform pg_advisory_xact_lock(hashtextextended(v_device, 24117));

  select * into v_user
  from public.registered_users
  where device_id = v_device
    and upper(regexp_replace(activation_code, '\s+', '', 'g')) = v_code
    and (expires_at is null or expires_at = 0 or expires_at > v_now)
  order by activated_at desc
  limit 1;

  if v_user.id is not null then
    v_token := encode(gen_random_bytes(32), 'hex');
    update public.registered_users
      set access_token_hash = encode(digest(v_token, 'sha256'), 'hex')
      where id = v_user.id
      returning * into v_user;
    return jsonb_build_object(
      'ok', true,
      'user', to_jsonb(v_user) - 'access_token_hash',
      'access_token', v_token
    );
  end if;

  select * into v_attempt
  from public.activation_attempts
  where device_id = v_device;

  if v_attempt.device_id is not null then
    if v_attempt.locked_until is not null and v_attempt.locked_until > v_now then
      return jsonb_build_object(
        'ok', false,
        'message', 'تم إيقاف المحاولات مؤقتاً. حاول بعد 30 دقيقة.',
        'retry_after_ms', v_attempt.locked_until - v_now
      );
    end if;
    if v_now - v_attempt.first_failed_at > v_window_ms then
      delete from public.activation_attempts where device_id = v_device;
    end if;
  end if;

  -- Serialize code creation/reactivation and consumption, then lock the row
  -- so used_count cannot be reset or oversubscribed by a concurrent admin.
  perform pg_advisory_xact_lock(hashtextextended(v_code, 24118));
  select * into v_code_row
  from public.allowed_codes
  where upper(regexp_replace(code, '\s+', '', 'g')) = v_code
    and active = true
    and used_count < max_uses
  for update;

  if v_code_row.code is null then
    insert into public.activation_attempts(
      device_id, fail_count, first_failed_at, locked_until
    )
    values (v_device, 1, v_now, null)
    on conflict (device_id) do update
    set
      fail_count = case
        when v_now - public.activation_attempts.first_failed_at > v_window_ms
          then 1
        else public.activation_attempts.fail_count + 1
      end,
      first_failed_at = case
        when v_now - public.activation_attempts.first_failed_at > v_window_ms
          then v_now
        else public.activation_attempts.first_failed_at
      end,
      locked_until = null
    returning * into v_attempt;

    if v_attempt.fail_count >= v_max_fails then
      update public.activation_attempts
      set locked_until = v_now + v_lockout_ms
      where device_id = v_device;
    end if;

    -- Do not RAISE here. Returning allows the counter update to commit.
    return jsonb_build_object(
      'ok', false,
      'message', 'كود التفعيل غير صحيح أو استُخدم بالكامل'
    );
  end if;

  update public.allowed_codes
  set used_count = used_count + 1
  where code = v_code_row.code;

  delete from public.activation_attempts where device_id = v_device;
  v_exp := case
    when v_code_row.duration_days = 0 then null
    else v_now + (v_code_row.duration_days::bigint * 86400000)
  end;
  v_token := encode(gen_random_bytes(32), 'hex');

  select * into v_user
  from public.registered_users
  where activation_code = v_code_row.code
    and pending = true
  order by activated_at desc
  limit 1
  for update;

  if v_user.id is not null then
    update public.registered_users
    set activated_at = v_now,
        expires_at = v_exp,
        device_id = v_device,
        access_token_hash = encode(digest(v_token, 'sha256'), 'hex'),
        pending = false
    where id = v_user.id
    returning * into v_user;
  else
    insert into public.registered_users(
      id,
      full_name,
      activation_code,
      activated_at,
      expires_at,
      device_id,
      access_token_hash,
      pending
    )
    values (
      gen_random_uuid()::text,
      v_name,
      v_code_row.code,
      v_now,
      v_exp,
      v_device,
      encode(digest(v_token, 'sha256'), 'hex'),
      false
    )
    returning * into v_user;
  end if;

  return jsonb_build_object(
    'ok', true,
    'user', to_jsonb(v_user) - 'access_token_hash',
    'access_token', v_token
  );
end;
$$;

drop function if exists public.get_my_registration_v2(text,text);

create or replace function public.get_my_registration_v2(
  p_user_id text,
  p_device_id text,
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user public.registered_users;
  v_token text;
  v_now bigint := floor(extract(epoch from clock_timestamp()) * 1000);
begin
  if length(trim(coalesce(p_user_id, ''))) > 128
     or length(trim(coalesce(p_device_id, ''))) > 128
     or length(trim(coalesce(p_token, ''))) < 48
     or length(trim(coalesce(p_token, ''))) > 256 then
    return jsonb_build_object('ok', false, 'message', 'طلب غير صالح');
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(trim(coalesce(p_device_id, '')), 24117)
  );
  select * into v_user
  from public.registered_users
  where id = trim(coalesce(p_user_id, ''))
    and device_id = trim(coalesce(p_device_id, ''))
    and pending = false
    and access_token_hash = encode(
      digest(trim(coalesce(p_token, '')), 'sha256'),
      'hex'
    )
    and (expires_at is null or expires_at = 0 or expires_at > v_now)
  limit 1;

  if v_user.id is null then
    return jsonb_build_object('ok', false, 'message', 'التفعيل غير موجود أو منتهي');
  end if;

  v_token := encode(gen_random_bytes(32), 'hex');
  update public.registered_users
  set access_token_hash = encode(digest(v_token, 'sha256'), 'hex')
  where id = v_user.id
  returning * into v_user;

  return jsonb_build_object(
    'ok', true,
    'user', to_jsonb(v_user) - 'access_token_hash',
    'access_token', v_token
  );
end;
$$;

drop function if exists public.deactivate_registration_v2(text,text);

create or replace function public.deactivate_registration_v2(
  p_user_id text,
  p_device_id text,
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_stored_device text;
begin
  if length(trim(coalesce(p_user_id, ''))) > 128
     or length(trim(coalesce(p_device_id, ''))) > 128
     or length(trim(coalesce(p_token, ''))) < 48
     or length(trim(coalesce(p_token, ''))) > 256 then
    return jsonb_build_object('ok', false, 'message', 'طلب غير صالح');
  end if;

  -- The random token is the deletion credential. Lock the matching row so a
  -- simultaneous token rotation cannot turn a real deletion into a false
  -- success. Do not require the cached installation id to be unchanged: it
  -- can legitimately be lost during an OS restore while the Keychain token
  -- is still available.
  select device_id into v_stored_device
  from public.registered_users
  where id = trim(coalesce(p_user_id, ''))
    and pending = false
    and access_token_hash = encode(
      digest(trim(coalesce(p_token, '')), 'sha256'),
      'hex'
    )
  for update;

  if v_stored_device is not null then
    delete from public.ai_safety_reports
    where registration_id = trim(coalesce(p_user_id, ''));
    delete from public.activation_attempts
    where device_id in (
      v_stored_device,
      trim(coalesce(p_device_id, ''))
    );
    delete from public.registered_users
    where id = trim(coalesce(p_user_id, ''));
  elsif exists (
    select 1 from public.registered_users
    where id = trim(coalesce(p_user_id, ''))
  ) then
    return jsonb_build_object('ok', false, 'message', 'جلسة التفعيل غير صالحة');
  end if;

  -- Idempotent by design: a repeated deletion request is still complete.
  return jsonb_build_object('ok', true);
end;
$$;

-- Called by the production backend with the service-role key. Never grant this
-- verifier to the public mobile roles.
create or replace function public.verify_activation_token(
  p_user_id text,
  p_token text
)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
    from public.registered_users ru
    where ru.id = trim(coalesce(p_user_id, ''))
      and ru.pending = false
      and ru.access_token_hash = encode(
        digest(coalesce(p_token, ''), 'sha256'),
        'hex'
      )
      and (
        ru.expires_at is null
        or ru.expires_at = 0
        or ru.expires_at > floor(extract(epoch from now()) * 1000)
      )
  );
$$;

-- Keep the old function body only so upgrades from the baseline schema remain
-- deterministic. Public execution is revoked below because the legacy result
-- cannot deliver the secure session token used by the production client.
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
  v_result jsonb;
  v_id text;
begin
  v_result := public.activate_registration_v2(
    p_full_name,
    p_code,
    p_device_id
  );
  if coalesce((v_result ->> 'ok')::boolean, false) then
    v_id := v_result -> 'user' ->> 'id';
    return query
      select ru.* from public.registered_users ru where ru.id = v_id;
  end if;
  return;
end;
$$;

-- Never expose activation-token hashes to the mobile admin client. Keep the
-- original composite return type for backward compatibility, but blank the
-- sensitive column in every returned row.
create or replace function public.admin_list_users()
returns setof public.registered_users
language sql
stable
security definer
set search_path = public
as $$
  select
    ru.id,
    ru.full_name,
    ru.activation_code,
    ru.activated_at,
    ru.expires_at,
    ru.device_id,
    null::text as access_token_hash,
    ru.pending
  from public.registered_users ru
  where public.is_eliteradiq_admin()
  order by ru.activated_at desc;
$$;

-- Codes displayed in the admin UI are those that can still be used.
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
    and ac.active = true
    and ac.used_count < ac.max_uses
  order by ac.code;
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
  if not public.is_eliteradiq_admin() then raise exception 'غير مصرح'; end if;
  if v_code = '' or length(v_code) < 12 or length(v_code) > 64 then
    raise exception 'يجب أن يتكون الكود من 12 محرفاً على الأقل';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_code, 24118));
  if exists (
    select 1 from public.registered_users
    where upper(regexp_replace(activation_code, '\s+', '', 'g')) = v_code
      and pending = false
  ) then
    raise exception 'هذا الكود مرتبط بتفعيل سابق؛ أنشئ كوداً جديداً';
  end if;

  insert into public.allowed_codes(
    code, duration_days, max_uses, used_count, active
  )
  values (v_code, 365, 1, 0, true)
  on conflict (code) do update
  set duration_days = 365,
      max_uses = 1,
      used_count = 0,
      active = true;
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
  if not public.is_eliteradiq_admin() then raise exception 'غير مصرح'; end if;
  update public.allowed_codes
  set active = false
  where upper(regexp_replace(code, '\s+', '', 'g')) =
    upper(regexp_replace(trim(coalesce(p_code, '')), '\s+', '', 'g'));

  delete from public.registered_users
  where pending = true
    and upper(regexp_replace(activation_code, '\s+', '', 'g')) =
      upper(regexp_replace(trim(coalesce(p_code, '')), '\s+', '', 'g'));
end;
$$;

-- Admin-created users are pending invitations. Activation binds the pending
-- record to the student's installation instead of creating a duplicate row.
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
  v_days integer := coalesce(p_duration_days, 0);
  v_now bigint := floor(extract(epoch from clock_timestamp()) * 1000);
begin
  if not public.is_eliteradiq_admin() then raise exception 'غير مصرح'; end if;
  if length(v_name) < 5
     or coalesce(array_length(regexp_split_to_array(v_name, '\s+'), 1), 0) < 3
     or length(v_name) > 160 then
    raise exception 'الاسم الثلاثي غير صالح';
  end if;
  if length(v_code) < 12 or length(v_code) > 64 then
    raise exception 'يجب أن يتكون الكود من 12 محرفاً على الأقل';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_code, 24118));
  if exists (
    select 1 from public.registered_users
    where upper(regexp_replace(activation_code, '\s+', '', 'g')) = v_code
      and pending = false
  ) then
    raise exception 'هذا الكود مرتبط بتفعيل سابق؛ أنشئ كوداً جديداً';
  end if;
  if v_days < 0 or v_days > 3650 then
    raise exception 'مدة التفعيل يجب أن تكون دائمة أو بين يوم و3650 يوماً';
  end if;

  insert into public.allowed_codes(
    code, duration_days, max_uses, used_count, active
  )
  values (v_code, v_days, 1, 0, true)
  on conflict (code) do update
  set duration_days = excluded.duration_days,
      max_uses = 1,
      used_count = 0,
      active = true;

  select * into v_user
  from public.registered_users
  where activation_code = v_code and pending = true
  order by activated_at desc
  limit 1;

  if v_user.id is null then
    insert into public.registered_users(
      id, full_name, activation_code, activated_at, expires_at, device_id, pending
    )
    values (
      gen_random_uuid()::text, v_name, v_code, v_now, null, 'PENDING', true
    )
    returning * into v_user;
  else
    update public.registered_users
    set full_name = v_name,
        activated_at = v_now,
        expires_at = null,
        device_id = 'PENDING',
        access_token_hash = null,
        pending = true
    where id = v_user.id
    returning * into v_user;
  end if;
  v_user.access_token_hash := null;
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
  if not public.is_eliteradiq_admin() then raise exception 'غير مصرح'; end if;
  if p_duration_days is not null
     and (p_duration_days < 0 or p_duration_days > 3650) then
    raise exception 'المدة يجب أن تكون بين 0 و3650 يوماً';
  end if;

  select * into v_user
  from public.registered_users
  where id = trim(coalesce(p_user_id, ''))
  for update;
  if v_user.id is null then raise exception 'المستخدم غير موجود'; end if;

  if v_user.pending then
    update public.allowed_codes
    set duration_days = coalesce(p_duration_days, 0)
    where code = v_user.activation_code;
    update public.registered_users
    set expires_at = null
    where id = v_user.id
    returning * into v_user;
  else
    v_exp := case
      when p_duration_days is null then null
      when p_duration_days = 0 then v_now - 1
      else v_now + (p_duration_days::bigint * 86400000)
    end;
    update public.registered_users
    set expires_at = v_exp
    where id = v_user.id
    returning * into v_user;
  end if;
  v_user.access_token_hash := null;
  return v_user;
end;
$$;

create or replace function public.admin_delete_user(p_user_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user public.registered_users;
begin
  if not public.is_eliteradiq_admin() then raise exception 'غير مصرح'; end if;
  select * into v_user
  from public.registered_users
  where id = trim(coalesce(p_user_id, ''));
  if v_user.pending then
    update public.allowed_codes set active = false
    where code = v_user.activation_code;
  end if;
  delete from public.ai_safety_reports where registration_id = v_user.id;
  delete from public.registered_users where id = v_user.id;
end;
$$;

revoke all on function public.activate_registration_v2(text,text,text)
  from public, anon, authenticated;
revoke all on function public.get_my_registration_v2(text,text,text)
  from public, anon, authenticated;
revoke all on function public.deactivate_registration_v2(text,text,text)
  from public, anon, authenticated;
revoke all on function public.verify_activation_token(text,text)
  from public, anon, authenticated;
revoke all on function public.activate_registration(text,text,text)
  from public, anon, authenticated;

-- Activation codes are checked only by the rate-limited production gateway.
-- The mobile client cannot invoke the privileged code-verification RPC
-- directly and therefore cannot bypass the gateway's source-address limit.
grant execute on function public.activate_registration_v2(text,text,text)
  to service_role;
grant execute on function public.get_my_registration_v2(text,text,text)
  to anon, authenticated;
grant execute on function public.deactivate_registration_v2(text,text,text)
  to anon, authenticated;
grant execute on function public.verify_activation_token(text,text)
  to service_role;

revoke all on function public.admin_list_codes() from public;
revoke all on function public.admin_list_users() from public;
revoke all on function public.admin_add_code(text) from public;
revoke all on function public.admin_delete_code(text) from public;
revoke all on function public.admin_add_user(text,text,integer) from public;
revoke all on function public.admin_update_user_duration(text,integer) from public;
revoke all on function public.admin_delete_user(text) from public;
grant execute on function public.admin_list_codes() to authenticated;
grant execute on function public.admin_list_users() to authenticated;
grant execute on function public.admin_add_code(text) to authenticated;
grant execute on function public.admin_delete_code(text) to authenticated;
grant execute on function public.admin_add_user(text,text,integer) to authenticated;
grant execute on function public.admin_update_user_duration(text,integer)
  to authenticated;
grant execute on function public.admin_delete_user(text)
  to authenticated;

-- Legacy read/delete RPCs do not authenticate a secure session token. Keep the
-- definitions only for migration compatibility, but remove mobile execution.
revoke all on function public.get_my_registration(text,text)
  from public, anon, authenticated;
revoke all on function public.deactivate_registration(text,text)
  from public, anon, authenticated;

-- Keep an infrastructure/WAF limit in front of `/api/activate` as a second
-- layer. The database device-id counter and the gateway source-address limit
-- protect different abuse paths.
