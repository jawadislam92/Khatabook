-- Test helpers: switch identity and assert outcomes.
create or replace function test.login(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create or replace function test.logout() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('role', 'postgres', true);
end $$;

create or replace function test.new_user(p_email text, p_name text) returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into auth.users(email, raw_user_meta_data)
    values (p_email, jsonb_build_object('display_name', p_name)) returning id into v;
  return v;
end $$;

-- Runs a statement as the current test identity and reports whether it raised.
create or replace function test.fails(p_sql text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return true;
end $$;

create or replace function test.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok   %', p_label;
  else
    insert into test.failures(label) values (p_label);
    raise warning 'FAIL %', p_label;
  end if;
end $$;
