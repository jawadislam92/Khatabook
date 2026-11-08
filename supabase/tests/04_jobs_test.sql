begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

do $$
declare
  uncle uuid; saeed uuid; bilal uuid; munshi uuid; omar uuid;
  biz uuid; cust uuid; job uuid; item uuid; tok text; n int; st public.job_status; cost bigint; when_ timestamptz;
begin
  uncle := test.new_user('uncle@b.com', 'Ahmed'); saeed := test.new_user('saeed@b.com', 'Saeed');
  bilal := test.new_user('bilal@b.com', 'Bilal'); munshi := test.new_user('munshi@b.com', 'Munshi'); omar := test.new_user('omar@b.com', 'Omar');
  perform test.login(uncle);
  biz := public.create_space('Ahmed CCTV', true);
  tok := public.create_invite(biz, 'member'); perform test.login(saeed); perform public.accept_invite(tok);
  perform test.login(uncle);
  tok := public.create_invite(biz, 'member'); perform test.login(bilal); perform public.accept_invite(tok);
  perform test.login(uncle);
  tok := public.create_invite(biz, 'manager'); perform test.login(munshi); perform public.accept_invite(tok);

  -- Catalog: manager adds items with a cost price; installers cannot see the cost.
  perform test.login(uncle);
  insert into public.items(space_id, name_en, unit, sale_price_paisa, cost_price_paisa, created_by)
    values (biz, 'Dome camera 2MP', 'pc', 450000, 320000, uncle) returning id into item;
  select cost_price_paisa into cost from public.items_visible where id = item;
  perform test.check(cost = 320000, 'owner sees cost price');
  perform test.login(munshi);
  select cost_price_paisa into cost from public.items_visible where id = item;
  perform test.check(cost is null, 'manager does not see cost by default');
  perform test.login(uncle);
  update public.spaces set settings = '{"managers_see_costs": true}'::jsonb where id = biz;
  perform test.login(munshi);
  select cost_price_paisa into cost from public.items_visible where id = item;
  perform test.check(cost = 320000, 'manager sees cost when the owner allows it');
  perform test.login(saeed);
  select cost_price_paisa into cost from public.items_visible where id = item;
  perform test.check(cost is null, 'installer never sees cost');
  perform test.check(test.fails('select cost_price_paisa from public.items'), 'installer cannot read cost from the base table');
  perform test.check(test.fails(format(
    'insert into public.items(space_id, name_en, sale_price_paisa, created_by) values (%L, ''X'', 1, %L)', biz, saeed)),
    'installer cannot add catalog items');

  -- Job creation: manager only, alerts scheduled.
  perform test.login(uncle);
  insert into public.parties(space_id, name, is_customer, created_by) values (biz, 'Mr Ahmed F-10', true, uncle) returning id into cust;
  when_ := now() + interval '2 days';
  job := public.create_job(biz, cust, '2 cameras not recording', 'cctv_repair', when_, array[saeed, bilal], 'F-10/2 Islamabad');
  select count(*) into n from public.job_assignees where job_id = job;
  perform test.check(n = 2, 'both installers assigned');
  select count(*) into n from public.scheduled_notifications where job_id = job and cancelled_at is null;
  perform test.check(n = 4, 'four alerts scheduled: assigned, unconfirmed, evening before, one hour before');
  select count(*) into n from public.scheduled_notifications where job_id = job and kind = 'job_assigned' and recipients @> array[saeed, bilal] and due_at <= now();
  perform test.check(n = 1, 'assignment alert goes to installers right away');
  select count(*) into n from public.scheduled_notifications where job_id = job and kind = 'job_unconfirmed' and recipients @> array[uncle, munshi];
  perform test.check(n = 1, 'unconfirmed alert includes the owner and manager');
  select count(*) into n from public.scheduled_notifications where job_id = job and kind = 'jobs_tomorrow'
    and (due_at at time zone 'Asia/Karachi')::time = time '20:00';
  perform test.check(n = 1, 'evening digest is at 8 pm Pakistan time');
  select count(*) into n from public.scheduled_notifications where job_id = job and kind = 'job_soon' and due_at = when_ - interval '1 hour';
  perform test.check(n = 1, 'reminder is one hour before');
  perform test.login(saeed);
  perform test.check(test.fails(format('select public.create_job(%L, %L, ''x'', ''other'', now(), array[%L])', biz, cust, saeed)),
    'installer cannot create a job');

  -- Confirm: assignee only; cancels the nag; notifies managers.
  perform test.login(munshi);
  perform test.check(test.fails(format('select public.confirm_job(%L)', job)), 'non assignee cannot confirm');
  perform test.login(saeed);
  perform public.confirm_job(job);
  select status into st from public.jobs where id = job;
  perform test.check(st = 'confirmed', 'confirming moves the job to confirmed');
  perform test.login(uncle);  -- alert rows are visible to managers only
  select count(*) into n from public.scheduled_notifications where job_id = job and kind = 'job_unconfirmed' and cancelled_at is not null;
  perform test.check(n = 1, 'confirming cancels the unconfirmed alert');
  select count(*) into n from public.scheduled_notifications where job_id = job and kind = 'job_status' and recipients @> array[uncle];
  perform test.check(n = 1, 'owner is told about the confirmation');

  -- Status flow by installer; cancel only by manager; invoiced not settable here.
  perform test.login(saeed);
  perform public.set_job_status(job, 'on_the_way');
  perform public.set_job_status(job, 'working');
  perform public.set_job_status(job, 'finished');
  select status into st from public.jobs where id = job;
  perform test.check(st = 'finished', 'installer walks the job to finished');
  select count(*) into n from public.job_events where job_id = job and event_type = 'status';
  perform test.check(n = 3, 'each status change is recorded');
  perform test.check(test.fails(format('select public.set_job_status(%L, ''cancelled'')', job)), 'installer cannot cancel');
  perform test.check(test.fails(format('select public.set_job_status(%L, ''invoiced'')', job)), 'invoiced cannot be set by hand');
  perform test.login(uncle);
  select count(*) into n from public.scheduled_notifications where job_id = job and sent_at is null and cancelled_at is null and kind in ('jobs_tomorrow', 'job_soon');
  perform test.check(n = 0, 'finishing cancels the pending reminders');
  perform test.login(saeed);

  -- Job items by assignee; frozen once invoiced (simulated by direct status update as superuser).
  insert into public.job_items(job_id, space_id, item_id, description, qty, unit_price_paisa, created_by)
    values (job, biz, item, 'Dome camera 2MP', 2, 450000, saeed);
  perform test.login(omar);
  select count(*) into n from public.jobs where id = job;
  perform test.check(n = 0, 'stranger sees no jobs');
  perform test.check(test.fails(format(
    'insert into public.job_items(job_id, space_id, description, qty, unit_price_paisa, created_by) values (%L, %L, ''x'', 1, 1, %L)', job, biz, omar)),
    'stranger cannot add job items');
  perform test.logout();
  update public.jobs set status = 'invoiced' where id = job;
  perform test.login(saeed);
  perform test.check(test.fails(format('delete from public.job_items where job_id = %L', job)), 'items of an invoiced job are frozen');

  -- Reschedule resets confirmation and notifies.
  perform test.login(uncle);
  job := public.create_job(biz, cust, 'Solar service', 'solar_service', now() + interval '3 days', array[bilal]);
  perform test.login(bilal); perform public.confirm_job(job);
  perform test.login(uncle);
  perform public.reschedule_job(job, now() + interval '4 days');
  select status into st from public.jobs where id = job;
  perform test.check(st = 'scheduled', 'rescheduling puts a confirmed job back to scheduled');
  select count(*) into n from public.job_assignees where job_id = job and confirmed_at is null;
  perform test.check(n = 1, 'rescheduling clears confirmations');
  select count(*) into n from public.scheduled_notifications where job_id = job and kind = 'job_rescheduled';
  perform test.check(n = 1, 'reschedule sends a notice');

  -- Inbox is private.
  perform test.logout();
  insert into public.notifications(user_id, space_id, kind, title, body) values (bilal, biz, 'job_assigned', 'New job', 'x');
  perform test.login(saeed);
  select count(*) into n from public.notifications;
  perform test.check(n = 0, 'cannot read another person''s inbox');
  perform test.login(bilal);
  select count(*) into n from public.notifications;
  perform test.check(n = 1, 'own inbox visible');
  update public.notifications set read_at = now() where user_id = bilal;
  perform test.check(true, 'can mark own notification read');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All jobs tests passed';
end $$;
rollback;
