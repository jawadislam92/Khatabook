-- "Can't finish today": the installer stops a job (everything optional), the
-- owner is alerted and sets a new date; items already on the job stay.
begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

do $$
declare
  uncle uuid; saeed uuid; stranger uuid; biz uuid; cust uuid; job uuid; job2 uuid; tok text; n int;
  st text; r text; sug timestamptz; when_ timestamptz;
begin
  uncle := test.new_user('uncle@h.com', 'Ahmed'); saeed := test.new_user('saeed@h.com', 'Saeed');
  stranger := test.new_user('x@h.com', 'X');
  perform test.login(uncle);
  biz := public.create_space('Ahmed CCTV', true);
  tok := public.create_invite(biz, 'member'); perform test.login(saeed); perform public.accept_invite(tok);
  perform test.login(uncle);
  insert into public.parties(space_id, name, is_customer, created_by) values (biz, 'Mr Ahmed', true, uncle) returning id into cust;
  job := public.create_job(biz, cust, 'Solar install', 'solar_install', now() + interval '1 day', array[saeed]);
  -- The owner lists items to take; the installer will see them on site.
  insert into public.job_items(job_id, space_id, description, qty, unit_price_paisa, created_by)
    values (job, biz, 'Panel 550W', 4, 3500000, uncle);

  -- Installer skips Confirm and On my way: straight to working.
  perform test.login(saeed);
  perform public.set_job_status(job, 'working');
  perform test.check((select status::text from public.jobs where id = job) = 'working', 'steps can be skipped');

  -- No electricity on site; nothing else filled in is also fine.
  perform test.login(stranger);
  perform test.check(test.fails(format('select public.report_job_problem(%L, ''no_power'')', job)),
    'someone outside the business cannot stop the job');
  perform test.login(saeed);
  sug := date_trunc('minute', now() + interval '3 days');
  perform public.report_job_problem(job, 'no_power', 'Breaker off, owner away', sug);
  select status::text, hold_reason into st, r from public.jobs where id = job;
  perform test.check(st = 'on_hold', 'the job now needs a new date');
  perform test.check(r = 'no_power', 'the reason is kept');
  perform test.check((select suggested_at from public.jobs where id = job) = sug, 'the suggested date is kept');
  select count(*) into n from public.job_events where job_id = job and event_type = 'on_hold';
  perform test.check(n = 1, 'the history shows it');
  perform test.check(test.fails(format('select public.set_job_status(%L, ''finished'')', job)),
    'it cannot be finished before a new date');
  perform test.check(test.fails(format('select public.set_job_status(%L, ''working'')', job)),
    'it cannot go back to working without a new date');
  perform test.check(test.fails(format('select public.set_job_status(%L, ''on_hold'')', job)),
    'on hold is only set through the report');
  perform test.check(test.fails(format('select public.reschedule_job(%L, now() + interval ''2 days'')', job)),
    'the installer does not set the new date');

  reset role;
  select count(*) into n from public.scheduled_notifications
    where job_id = job and kind = 'job_status' and payload->>'status' = 'on_hold' and recipients @> array[uncle];
  perform test.check(n = 1, 'the owner is alerted');
  select count(*) into n from public.scheduled_notifications
    where job_id = job and kind in ('jobs_tomorrow', 'job_soon') and sent_at is null and cancelled_at is null;
  perform test.check(n = 0, 'reminders for the old time are stopped');

  -- Owner sets the new date: back to scheduled, items kept, hold cleared.
  perform test.login(uncle);
  when_ := date_trunc('minute', now() + interval '4 days');
  perform public.reschedule_job(job, when_);
  select status::text, hold_reason into st, r from public.jobs where id = job;
  perform test.check(st = 'scheduled', 'a new date makes it scheduled again');
  perform test.check(r is null, 'the hold reason is cleared');
  perform test.check((select count(*) from public.job_items where job_id = job) = 1, 'items on the job stay');

  -- With nothing filled in at all.
  perform test.login(saeed);
  perform public.report_job_problem(job);
  perform test.check((select status::text from public.jobs where id = job) = 'on_hold', 'a report needs no reason');

  -- A finished job cannot be put on hold.
  perform test.login(uncle);
  job2 := public.create_job(biz, cust, 'Camera fix', 'cctv_repair', now() + interval '1 day', array[saeed]);
  perform test.login(saeed);
  perform public.set_job_status(job2, 'finished');
  perform test.check(test.fails(format('select public.report_job_problem(%L)', job2)), 'a finished job cannot be stopped');

  -- An owner can still cancel a job on hold.
  perform test.login(uncle);
  perform public.set_job_status(job, 'cancelled');
  perform test.check((select status::text from public.jobs where id = job) = 'cancelled', 'a job on hold can be cancelled');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All job hold tests passed';
end $$;
rollback;
