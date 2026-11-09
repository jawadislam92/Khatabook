begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

-- The API attaches a person's display name to entries, job events and job
-- assignees by following a foreign key to profiles. Without those keys the
-- requests fail with PGRST200, so their presence is checked here.
do $$
declare
  ali uuid; sara uuid; sp uuid; party uuid; job uuid; n int; who text;
begin
  select count(*) into n from pg_constraint
   where contype = 'f' and confrelid = 'public.profiles'::regclass
     and conrelid = 'public.entries'::regclass
     and conkey = array[(select attnum from pg_attribute where attrelid = 'public.entries'::regclass and attname = 'created_by')];
  perform test.check(n = 1, 'entries.created_by links to profiles');

  select count(*) into n from pg_constraint
   where contype = 'f' and confrelid = 'public.profiles'::regclass
     and conrelid = 'public.job_events'::regclass
     and conkey = array[(select attnum from pg_attribute where attrelid = 'public.job_events'::regclass and attname = 'actor_id')];
  perform test.check(n = 1, 'job_events.actor_id links to profiles');

  select count(*) into n from pg_constraint
   where contype = 'f' and confrelid = 'public.profiles'::regclass
     and conrelid = 'public.job_assignees'::regclass
     and conkey = array[(select attnum from pg_attribute where attrelid = 'public.job_assignees'::regclass and attname = 'user_id')]
     and confdeltype = 'c';
  perform test.check(n = 1, 'job_assignees.user_id links to profiles and follows the user when deleted');

  -- The join the app relies on works end to end: an entry carries its author's name.
  ali := test.new_user('ali@x.com', 'Ali'); sara := test.new_user('sara@x.com', 'Sara');
  perform test.login(ali);
  sp := public.create_space('Dukaan', true);
  insert into public.parties(space_id, name, created_by) values (sp, 'Customer', ali) returning id into party;
  insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, created_by)
    values (sp, (select id from public.books where space_id = sp and is_default), party, 'gave', 50000, ali);
  select p.display_name into who from public.entries e join public.profiles p on p.user_id = e.created_by where e.space_id = sp;
  perform test.check(who = 'Ali', 'entry joins to its author through profiles');

  job := public.create_job(sp, party, 'Install', 'cctv_install'::public.job_type, now() + interval '1 day', array[ali]);
  select count(*) into n from public.job_assignees a join public.profiles p on p.user_id = a.user_id where a.job_id = job;
  perform test.check(n = 1, 'job assignee joins to a profile');
  select count(*) into n from public.job_events ev left join public.profiles p on p.user_id = ev.actor_id where ev.job_id = job and ev.actor_id is not null and p.user_id is null;
  perform test.check(n = 0, 'every job event actor has a profile');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All profile link tests passed';
end $$;
rollback;
