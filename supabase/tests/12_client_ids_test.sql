-- Offline phones make ids for new jobs and visits. Sending the same one
-- twice gives back the same job, never a second one. Old app versions that
-- send no id keep working.
begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

do $$
declare
  uncle uuid; saeed uuid; biz uuid; other uuid; cust uuid; tok text; a uuid; b uuid; f uuid; f2 uuid; n int;
  jid uuid := gen_random_uuid(); vid uuid := gen_random_uuid();
begin
  uncle := test.new_user('uncle@c.com', 'Ahmed'); saeed := test.new_user('saeed@c.com', 'Saeed');
  perform test.login(uncle);
  biz := public.create_space('Ahmed CCTV', true);
  other := public.create_space('Other shop', true);
  tok := public.create_invite(biz, 'member'); perform test.login(saeed); perform public.accept_invite(tok);
  perform test.login(uncle);
  insert into public.parties(space_id, name, is_customer, created_by) values (biz, 'Mr Ahmed', true, uncle) returning id into cust;

  a := public.create_job(biz, cust, 'Install', 'cctv_install', now() + interval '1 day', array[saeed], p_id => jid);
  b := public.create_job(biz, cust, 'Install', 'cctv_install', now() + interval '1 day', array[saeed], p_id => jid);
  perform test.check(a = jid and b = jid, 'the phone''s id is used, and sending twice returns it');
  select count(*) into n from public.jobs where id = jid;
  perform test.check(n = 1, 'only one job');
  select count(*) into n from public.job_assignees where job_id = jid;
  perform test.check(n = 1, 'the team is not added twice');
  perform test.check(test.fails(format(
    'select public.create_job(%L, %L, ''x'', ''other'', now(), array[]::uuid[], p_id => %L)', other, cust, jid)),
    'an id from another book is refused');

  -- Old app: no id.
  a := public.create_job(biz, cust, 'Repair', 'cctv_repair', now() + interval '2 days', array[saeed]);
  perform test.check(a is not null and a <> jid, 'without an id the server makes one');

  -- Another visit with an id, sent twice.
  perform test.login(saeed);
  perform public.set_job_status(jid, 'finished');
  f := public.book_follow_up(jid, now() + interval '3 days', 'One more camera', null, vid);
  f2 := public.book_follow_up(jid, now() + interval '3 days', 'One more camera', null, vid);
  perform test.check(f = vid and f2 = vid, 'a visit sent twice gives back the same visit');
  select count(*) into n from public.jobs where follow_up_of = jid;
  perform test.check(n = 1, 'only one visit');
  f := public.book_follow_up(jid, now() + interval '4 days');
  perform test.check(f is not null and f <> vid, 'without an id a visit still books');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All client id tests passed';
end $$;
rollback;
