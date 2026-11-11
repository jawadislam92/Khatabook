-- "Book another visit": after a job is done the installer or the owner books
-- a new job for the same customer and team at a new time.
begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

do $$
declare
  uncle uuid; saeed uuid; bilal uuid; stranger uuid; biz uuid; cust uuid; job uuid; nxt uuid; nxt2 uuid; tok text;
  when_ timestamptz; n int;
begin
  uncle := test.new_user('uncle@f.com', 'Ahmed'); saeed := test.new_user('saeed@f.com', 'Saeed');
  bilal := test.new_user('bilal@f.com', 'Bilal'); stranger := test.new_user('x@f.com', 'X');
  perform test.login(uncle);
  biz := public.create_space('Ahmed CCTV', true);
  tok := public.create_invite(biz, 'member'); perform test.login(saeed); perform public.accept_invite(tok);
  perform test.login(uncle);
  tok := public.create_invite(biz, 'member'); perform test.login(bilal); perform public.accept_invite(tok);
  perform test.login(uncle);
  insert into public.parties(space_id, name, is_customer, created_by) values (biz, 'Mr Ahmed', true, uncle) returning id into cust;
  job := public.create_job(biz, cust, '4 cameras install', 'cctv_install', now() - interval '1 day', array[saeed],
                           'House 12, F-10', 'Gate code 1234');
  perform test.login(saeed);
  perform public.set_job_status(job, 'finished');

  -- The customer asks for one more camera: the installer books it himself.
  when_ := date_trunc('minute', now() + interval '1 day');
  perform test.login(stranger);
  perform test.check(test.fails(format('select public.book_follow_up(%L, now() + interval ''1 day'')', job)),
    'someone outside the business cannot book a visit');
  perform test.login(bilal);
  perform test.check(test.fails(format('select public.book_follow_up(%L, now() + interval ''1 day'')', job)),
    'a member who was not on the job cannot book from it');
  perform test.login(saeed);
  perform test.check(test.fails(format('select public.book_follow_up(%L, null)', job)), 'a date is needed');
  nxt := public.book_follow_up(job, when_, 'Add 1 more camera');

  reset role;
  perform test.check((select customer_id from public.jobs where id = nxt) = cust, 'same customer');
  perform test.check((select address from public.jobs where id = nxt) = 'House 12, F-10', 'same address');
  perform test.check((select notes from public.jobs where id = nxt) = 'Gate code 1234', 'notes carried over');
  perform test.check((select title from public.jobs where id = nxt) = 'Add 1 more camera', 'the new work has its own title');
  perform test.check((select status::text from public.jobs where id = nxt) = 'scheduled', 'the new visit is scheduled');
  perform test.check((select scheduled_at from public.jobs where id = nxt) = when_, 'at the new time');
  perform test.check((select follow_up_of from public.jobs where id = nxt) = job, 'it remembers the first job');
  perform test.check(exists (select 1 from public.job_assignees where job_id = nxt and user_id = saeed), 'same team goes');
  perform test.check((select status::text from public.jobs where id = job) = 'finished', 'the first job stays finished');
  perform test.check(exists (select 1 from public.job_events where job_id = job and event_type = 'follow_up'),
    'the first job shows the new visit in its history');
  select count(*) into n from public.scheduled_notifications
    where job_id = nxt and kind = 'job_status' and payload->>'status' = 'follow_up' and recipients @> array[uncle]
      and cancelled_at is null;
  perform test.check(n = 1, 'the owner is alerted, and the alert is not cancelled');
  select count(*) into n from public.scheduled_notifications
    where job_id = job and kind = 'job_status' and payload->>'status' = 'finished' and cancelled_at is null;
  perform test.check(n = 1, 'the job finished alert is not cancelled');
  select count(*) into n from public.scheduled_notifications where job_id = nxt and kind = 'job_assigned' and recipients @> array[saeed];
  perform test.check(n = 1, 'the team gets the usual new job alert');

  -- Moving the new visit sends "job moved", and it stays queued.
  perform test.login(uncle);
  perform public.reschedule_job(nxt, when_ + interval '2 hours');
  reset role;
  select count(*) into n from public.scheduled_notifications
    where job_id = nxt and kind = 'job_rescheduled' and cancelled_at is null;
  perform test.check(n = 1, 'the job moved alert is not cancelled');
  select count(*) into n from public.scheduled_notifications
    where job_id = nxt and kind = 'job_soon' and cancelled_at is null;
  perform test.check(n = 1, 'reminders are set again for the new time, once');

  -- The owner can book one too, from a billed or any job, without a title.
  perform test.login(uncle);
  nxt2 := public.book_follow_up(job, when_ + interval '7 days');
  perform test.check((select title from public.jobs where id = nxt2) = '4 cameras install', 'title defaults to the first job');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All follow up tests passed';
end $$;
rollback;
