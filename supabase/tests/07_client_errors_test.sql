begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- A signed in user can add an error report about themself and do nothing
-- else with the table. Only the service role reads it.
do $$
declare
  ali uuid; sara uuid; n int; who uuid;
begin
  ali := test.new_user('ali@x.com', 'Ali'); sara := test.new_user('sara@x.com', 'Sara');

  perform test.login(ali);
  perform test.check(
    not test.fails($q$insert into public.client_errors(source, message, screen, app_version, platform)
                      values ('provider', 'TimeoutException after 0:00:30', '/space/1/job/2', '0.1.0', 'android')$q$),
    'a signed in user can report an error');
  perform test.check(
    test.fails(format($q$insert into public.client_errors(user_id, source, message) values (%L, 'flutter', 'x')$q$, sara)),
    'a report cannot be filed in someone else''s name');
  perform test.check(
    test.fails($q$select count(*) from public.client_errors$q$),
    'a user cannot read reports, not even their own');
  perform test.check(
    test.fails($q$update public.client_errors set message = 'changed'$q$),
    'a user cannot change reports');
  perform test.check(
    test.fails($q$delete from public.client_errors$q$),
    'a user cannot delete reports');
  perform test.check(
    test.fails($q$insert into public.client_errors(source, message) values ('other', 'x')$q$),
    'an unknown source is rejected');
  perform test.check(
    test.fails($q$insert into public.client_errors(source, message) values ('flutter', '')$q$),
    'an empty message is rejected');
  perform test.check(
    test.fails(format($q$insert into public.client_errors(source, message) values ('flutter', %L)$q$, repeat('x', 2001))),
    'a message over 2000 characters is rejected');

  perform test.logout();
  perform test.check(
    not has_table_privilege('anon', 'public.client_errors', 'insert, select, update, delete'),
    'a signed out visitor has no rights on the table');
  perform test.check(
    not has_table_privilege('authenticated', 'public.client_errors', 'select, update, delete'),
    'a signed in user holds insert and nothing more');

  select count(*), min(user_id::text)::uuid into n, who from public.client_errors;
  perform test.check(n = 1, 'exactly the one valid report was stored');
  perform test.check(who = ali, 'the report carries the reporter''s id without the app sending it');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All client error tests passed';
end $$;
rollback;
