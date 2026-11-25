-- How many alerts a job gives, and phones that change hands.
begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
create function test.waiting(p_job uuid, p_kind text) returns int language sql security definer as $$
  select count(*)::int from public.scheduled_notifications
    where job_id = p_job and kind::text = p_kind and sent_at is null and cancelled_at is null $$;
create function test.assigned_to(p_job uuid) returns uuid[] language sql security definer as $$
  select recipients from public.scheduled_notifications
    where job_id = p_job and kind = 'job_assigned' and sent_at is null and cancelled_at is null $$;
create function test.mark_assigned_sent(p_job uuid) returns void language sql security definer as $$
  update public.scheduled_notifications set sent_at = now() where job_id = p_job and kind = 'job_assigned' $$;
create function test.phone_owner(p_token text) returns uuid language sql security definer as $$
  select user_id from public.devices where fcm_token = p_token $$;
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

do $$
declare
  uncle uuid; mgr uuid; saeed uuid; bilal uuid; biz uuid; cust uuid; j uuid; k uuid; nxt uuid; tok text;
  v_at timestamptz := now() + interval '3 days';
begin
  uncle := test.new_user('uncle@g.com', 'Ahmed'); mgr := test.new_user('mgr@g.com', 'Munshi');
  saeed := test.new_user('saeed@g.com', 'Saeed'); bilal := test.new_user('bilal@g.com', 'Bilal');
  perform test.login(uncle);
  biz := public.create_space('Ahmed CCTV', true);
  tok := public.create_invite(biz, 'manager'); perform test.login(mgr); perform public.accept_invite(tok);
  perform test.login(uncle);
  tok := public.create_invite(biz, 'member'); perform test.login(saeed); perform public.accept_invite(tok);
  perform test.login(uncle);
  tok := public.create_invite(biz, 'member'); perform test.login(bilal); perform public.accept_invite(tok);
  perform test.login(uncle);
  insert into public.parties(space_id, name, is_customer, created_by) values (biz, 'Mr Ahmed', true, uncle) returning id into cust;

  -- No setting: as before.
  j := public.create_job(biz, cust, 'A', 'cctv_install', v_at, array[saeed]);
  perform test.check(test.waiting(j, 'job_assigned') = 1 and test.waiting(j, 'job_unconfirmed') = 1
    and test.waiting(j, 'jobs_tomorrow') = 1 and test.waiting(j, 'job_soon') = 1, 'normal is what it always was');

  -- Changing one job.
  perform public.set_job_alerts(j, '{"level":"many"}');
  perform test.check(test.waiting(j, 'job_unconfirmed') = 3 and test.waiting(j, 'job_soon') = 2, 'many: 3 repeats, 2 before');
  perform test.check(test.waiting(j, 'job_assigned') = 1, 'changing the level does not send New job again');
  perform public.set_job_alerts(j, '{"level":"custom","repeats":99,"every":1,"evening":false,"before":[120,30,10],"updates":false}');
  perform test.check(test.waiting(j, 'job_unconfirmed') = 5 and test.waiting(j, 'job_soon') = 3
    and test.waiting(j, 'jobs_tomorrow') = 0, 'own choice, kept within limits');
  perform test.check(test.fails(format('select public.set_job_alerts(%L, %L)', j, '{"level":"silly"}')), 'unknown level refused');
  perform test.login(saeed);
  perform test.check(test.fails(format('select public.set_job_alerts(%L, %L)', j, '{"level":"few"}')), 'an installer cannot change alerts');

  -- Updates off: the steps are quiet, finishing is not.
  perform public.set_job_status(j, 'on_the_way');
  perform test.check(test.waiting(j, 'job_status') = 0, 'updates off: on the way is quiet');
  perform public.set_job_status(j, 'finished');
  perform test.check(test.waiting(j, 'job_status') = 1, 'finished always reaches the owner');

  -- Another visit keeps the choice.
  nxt := public.book_follow_up(j, v_at + interval '1 day');
  perform test.check(test.waiting(nxt, 'job_soon') = 3, 'another visit keeps the choice');

  -- Set while creating.
  perform test.login(mgr);
  k := public.create_job(biz, cust, 'B', 'cctv_install', v_at, array[saeed], p_alerts => '{"level":"few"}');
  perform test.check(test.waiting(k, 'job_assigned') = 1 and test.waiting(k, 'job_unconfirmed') = 0
    and test.waiting(k, 'jobs_tomorrow') = 0 and test.waiting(k, 'job_soon') = 0, 'few: New job only');

  -- The business default: owner only, and only jobs without their own choice.
  perform test.check(test.fails(format('select public.set_space_alerts(%L, %L)', biz, '{"level":"many"}')), 'a manager cannot change the business default');
  perform test.login(uncle);
  perform public.set_space_alerts(biz, '{"level":"many"}');
  perform test.check(test.waiting(k, 'job_soon') = 0, 'a job with its own choice is left alone');
  perform public.set_job_alerts(k, null);
  perform test.check(test.waiting(k, 'job_soon') = 2, 'back to the business default');

  -- Team changes: only the new person is told, unless the first is still waiting.
  perform public.set_job_assignees(k, array[saeed, bilal]);
  perform test.check(test.assigned_to(k) @> array[saeed, bilal], 'not sent yet: both are told');
  perform test.mark_assigned_sent(k);
  perform public.set_job_assignees(k, array[saeed]);
  perform test.check(test.assigned_to(k) is null, 'taking someone off tells nobody');
  perform public.set_job_assignees(k, array[saeed, bilal]);
  perform test.check(test.assigned_to(k) = array[bilal], 'only the added person gets New job');

  -- Someone confirmed: changing the level does not nag again.
  perform test.login(saeed); perform public.confirm_job(k);
  perform test.login(uncle); perform public.set_job_alerts(k, '{"level":"many"}');
  perform test.check(test.waiting(k, 'job_unconfirmed') = 0, 'no nagging once someone confirmed');

  -- A phone changes hands.
  perform test.login(saeed); perform public.register_device('token-0001', 'android', '1.3.0');
  perform test.login(bilal); perform public.register_device('token-0001', 'android', '1.3.0');
  perform test.check(test.phone_owner('token-0001') = bilal, 'the phone follows the last sign in');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All alert settings tests passed';
end $$;
rollback;
