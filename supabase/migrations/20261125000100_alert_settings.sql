-- How many alerts a job gives. The owner sets a default for the business
-- (spaces.settings -> 'job_alerts') and an owner or manager can change any
-- single job (jobs.alert_settings, null means the business default).
-- "New job" itself can never be switched off.
--
-- Stored as {"level": "few" | "normal" | "many"} or
-- {"level": "custom", "repeats": 0-5, "every": 5-120 minutes,
--  "evening": true/false, "before": [minutes, up to 4], "updates": true/false}

create or replace function public.job_alert_plan(p jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  v_before int[];
begin
  case coalesce(p->>'level', 'normal')
    when 'few' then
      return '{"repeats":0,"every":30,"evening":false,"before":[],"updates":false}'::jsonb;
    when 'normal' then
      return '{"repeats":1,"every":30,"evening":true,"before":[60],"updates":true}'::jsonb;
    when 'many' then
      return '{"repeats":3,"every":15,"evening":true,"before":[60,15],"updates":true}'::jsonb;
    when 'custom' then
      select coalesce(array_agg(distinct least(greatest(v::int, 5), 1440)), '{}') into v_before
        from (select v from jsonb_array_elements_text(coalesce(p->'before', '[]'::jsonb)) v limit 4) t;
      return jsonb_build_object(
        'repeats', least(greatest(coalesce((p->>'repeats')::int, 1), 0), 5),
        'every', least(greatest(coalesce((p->>'every')::int, 30), 5), 120),
        'evening', coalesce((p->>'evening')::boolean, true),
        'before', to_jsonb(v_before),
        'updates', coalesce((p->>'updates')::boolean, true));
    else
      raise exception 'Unknown alert level' using errcode = 'check_violation';
  end case;
end $$;
revoke execute on function public.job_alert_plan(jsonb) from public, anon;

alter table public.jobs add column alert_settings jsonb;

create or replace function public.alert_plan_for(p_job uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select public.job_alert_plan(coalesce(j.alert_settings, s.settings->'job_alerts'))
    from public.jobs j join public.spaces s on s.id = j.space_id where j.id = p_job
$$;
revoke execute on function public.alert_plan_for(uuid) from public, anon, authenticated;

-- Bad settings are refused on the way in, so alerts can never break on them.
create or replace function public.check_job_alerts()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.alert_settings := nullif(new.alert_settings, 'null'::jsonb);
  if tg_op = 'INSERT' and new.alert_settings is null and new.follow_up_of is not null then
    -- Another visit keeps the choice made on the first job.
    select alert_settings into new.alert_settings from public.jobs where id = new.follow_up_of;
  end if;
  if new.alert_settings is not null then perform public.job_alert_plan(new.alert_settings); end if;
  return new;
end $$;
revoke execute on function public.check_job_alerts() from public, anon, authenticated;
create trigger jobs_check_alerts before insert or update of alert_settings on public.jobs
  for each row execute function public.check_job_alerts();

create or replace function public.check_space_alerts()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.settings ? 'job_alerts' then perform public.job_alert_plan(new.settings->'job_alerts'); end if;
  return new;
end $$;
revoke execute on function public.check_space_alerts() from public, anon, authenticated;
create trigger spaces_check_alerts before insert or update of settings on public.spaces
  for each row execute function public.check_space_alerts();

-- The reminders of a job, worked out again from its settings.
create or replace function public.schedule_job_reminders(p_job uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  j public.jobs%rowtype;
  v_assignees uuid[];
  v_all uuid[];
  v_payload jsonb;
  v_plan jsonb;
  v_due timestamptz;
  m int;
begin
  select * into j from public.jobs where id = p_job;
  update public.scheduled_notifications set cancelled_at = now()
    where job_id = p_job and sent_at is null and cancelled_at is null
      and kind in ('job_unconfirmed', 'jobs_tomorrow', 'job_soon');
  if j.status::text in ('cancelled', 'finished', 'invoiced', 'paid', 'on_hold') then return; end if;
  v_assignees := public.job_assignee_ids(p_job);
  if array_length(v_assignees, 1) is null then return; end if;
  select array_agg(distinct u) into v_all from unnest(v_assignees || public.space_managers(j.space_id)) u;
  v_payload := jsonb_build_object('job_id', j.id, 'title', j.title, 'scheduled_at', j.scheduled_at,
                                  'customer_id', j.customer_id, 'space_id', j.space_id);
  v_plan := public.alert_plan_for(p_job);
  -- Nobody confirmed yet. Dropped at send time once someone has. After the
  -- first one, repeats stop at the job's own time.
  if j.status = 'scheduled'
     and not exists (select 1 from public.job_assignees where job_id = p_job and confirmed_at is not null) then
    for i in 1..(v_plan->>'repeats')::int loop
      v_due := now() + i * (v_plan->>'every')::int * interval '1 minute';
      exit when i > 1 and v_due >= j.scheduled_at;
      insert into public.scheduled_notifications(space_id, kind, due_at, job_id, recipients, payload)
        values (j.space_id, 'job_unconfirmed', v_due, j.id, v_all, v_payload);
    end loop;
  end if;
  if (v_plan->>'evening')::boolean and public.evening_before(j.scheduled_at) > now() then
    insert into public.scheduled_notifications(space_id, kind, due_at, job_id, recipients, payload)
      values (j.space_id, 'jobs_tomorrow', public.evening_before(j.scheduled_at), j.id, v_all, v_payload);
  end if;
  for m in select v::int from jsonb_array_elements_text(v_plan->'before') v loop
    if j.scheduled_at - m * interval '1 minute' > now() then
      insert into public.scheduled_notifications(space_id, kind, due_at, job_id, recipients, payload)
        values (j.space_id, 'job_soon', j.scheduled_at - m * interval '1 minute', j.id, v_assignees,
                v_payload || jsonb_build_object('minutes', m));
    end if;
  end loop;
end $$;
revoke execute on function public.schedule_job_reminders(uuid) from public, anon, authenticated;

create or replace function public.schedule_job_alerts(p_job uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  j public.jobs%rowtype;
  v_assignees uuid[];
begin
  select * into j from public.jobs where id = p_job;
  update public.scheduled_notifications set cancelled_at = now()
    where job_id = p_job and sent_at is null and cancelled_at is null and kind = 'job_assigned';
  perform public.schedule_job_reminders(p_job);
  if j.status in ('cancelled', 'finished', 'invoiced', 'paid') then return; end if;
  v_assignees := public.job_assignee_ids(p_job);
  if array_length(v_assignees, 1) is null then return; end if;
  insert into public.scheduled_notifications(space_id, kind, due_at, job_id, recipients, payload)
    values (j.space_id, 'job_assigned', now(), j.id, v_assignees,
            jsonb_build_object('job_id', j.id, 'title', j.title, 'scheduled_at', j.scheduled_at,
                               'customer_id', j.customer_id, 'space_id', j.space_id));
end $$;

-- Progress steps (confirmed, on the way, started) can be switched off.
-- Finished, stopped and another visit always reach the owner.
create or replace function public.notify_now(p_space uuid, p_kind public.notification_kind, p_job uuid, p_recipients uuid[], p_payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if array_length(p_recipients, 1) is null then return; end if;
  if p_kind = 'job_status' and p_job is not null
     and coalesce(p_payload->>'status', '') in ('confirmed', 'on_the_way', 'working')
     and not coalesce((public.alert_plan_for(p_job)->>'updates')::boolean, true) then
    return;
  end if;
  insert into public.scheduled_notifications(space_id, kind, due_at, job_id, recipients, payload)
    values (p_space, p_kind, now(), p_job, p_recipients, p_payload);
end $$;

-- Changing the team tells only the people who have not been told yet.
create or replace function public.set_job_assignees(p_job uuid, p_assignees uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare
  j public.jobs%rowtype;
  u uuid;
  v_told uuid[];
  v_new uuid[];
begin
  select * into j from public.jobs where id = p_job;
  if not public.has_role_at_least(j.space_id, 'manager') then
    raise exception 'Only an owner or manager can assign jobs' using errcode = '42501';
  end if;
  -- Told: already on the job and no "new job" alert still waiting for them.
  select coalesce(array_agg(a.user_id), '{}') into v_told from public.job_assignees a
    where a.job_id = p_job and not exists (
      select 1 from public.scheduled_notifications s where s.job_id = p_job and s.kind = 'job_assigned'
        and s.sent_at is null and s.cancelled_at is null and a.user_id = any(s.recipients));
  delete from public.job_assignees where job_id = p_job and not (user_id = any(coalesce(p_assignees, '{}')));
  foreach u in array coalesce(p_assignees, '{}') loop
    if exists (select 1 from public.space_members where space_id = j.space_id and user_id = u) then
      insert into public.job_assignees(job_id, user_id, space_id) values (p_job, u, j.space_id) on conflict do nothing;
    end if;
  end loop;
  insert into public.job_events(job_id, space_id, event_type, actor_id) values (p_job, j.space_id, 'assigned', auth.uid());
  perform public.schedule_job_alerts(p_job);
  select array_agg(user_id) into v_new from public.job_assignees where job_id = p_job and not (user_id = any(v_told));
  if v_new is null then
    update public.scheduled_notifications set cancelled_at = now()
      where job_id = p_job and kind = 'job_assigned' and sent_at is null and cancelled_at is null;
  else
    update public.scheduled_notifications set recipients = v_new
      where job_id = p_job and kind = 'job_assigned' and sent_at is null and cancelled_at is null;
  end if;
end $$;

drop function public.create_job(uuid, uuid, text, public.job_type, timestamptz, uuid[], text, text, bigint, uuid);
create function public.create_job(
  p_space uuid, p_customer uuid, p_title text, p_type public.job_type, p_scheduled_at timestamptz,
  p_assignees uuid[], p_address text default null, p_notes text default null, p_estimate_paisa bigint default null,
  p_id uuid default null, p_alerts jsonb default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_job uuid;
  u uuid;
begin
  if not public.has_role_at_least(p_space, 'manager') then
    raise exception 'Only an owner or manager can create jobs' using errcode = '42501';
  end if;
  if p_id is not null and exists (select 1 from public.jobs where id = p_id) then
    if exists (select 1 from public.jobs where id = p_id and space_id = p_space) then
      return p_id; -- sent twice: the first one counted
    end if;
    raise exception 'Job id already used' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.parties where id = p_customer and space_id = p_space and deleted_at is null) then
    raise exception 'Customer not in this space' using errcode = 'check_violation';
  end if;
  insert into public.jobs(id, space_id, customer_id, title, job_type, scheduled_at, address, notes, estimate_paisa,
                          created_by, alert_settings)
    values (coalesce(p_id, gen_random_uuid()), p_space, p_customer, p_title, p_type, p_scheduled_at, p_address, p_notes,
            p_estimate_paisa, auth.uid(), p_alerts)
    returning id into v_job;
  insert into public.job_events(job_id, space_id, event_type, to_status, actor_id)
    values (v_job, p_space, 'created', 'scheduled', auth.uid());
  foreach u in array coalesce(p_assignees, '{}') loop
    if exists (select 1 from public.space_members where space_id = p_space and user_id = u) then
      insert into public.job_assignees(job_id, user_id, space_id) values (v_job, u, p_space) on conflict do nothing;
      insert into public.job_events(job_id, space_id, event_type, actor_id, note) values (v_job, p_space, 'assigned', auth.uid(), u::text);
    end if;
  end loop;
  perform public.schedule_job_alerts(v_job);
  return v_job;
end $$;
revoke execute on function public.create_job(uuid, uuid, text, public.job_type, timestamptz, uuid[], text, text, bigint, uuid, jsonb) from public, anon;
grant execute on function public.create_job(uuid, uuid, text, public.job_type, timestamptz, uuid[], text, text, bigint, uuid, jsonb) to authenticated;

-- One job. Null goes back to the business default.
create or replace function public.set_job_alerts(p_job uuid, p_alerts jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_space uuid;
begin
  select space_id into v_space from public.jobs where id = p_job;
  if v_space is null or not public.has_role_at_least(v_space, 'manager') then
    raise exception 'Only an owner or manager can change alerts' using errcode = '42501';
  end if;
  update public.jobs set alert_settings = p_alerts where id = p_job;
  perform public.schedule_job_reminders(p_job);
end $$;
revoke execute on function public.set_job_alerts(uuid, jsonb) from public, anon;
grant execute on function public.set_job_alerts(uuid, jsonb) to authenticated;

-- The business default, for every open job without its own choice.
create or replace function public.set_space_alerts(p_space uuid, p_alerts jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_job uuid;
begin
  if not public.has_role_at_least(p_space, 'owner') then
    raise exception 'Only the owner can change the business alerts' using errcode = '42501';
  end if;
  update public.spaces
    set settings = settings || jsonb_build_object('job_alerts', coalesce(p_alerts, '{"level":"normal"}'::jsonb))
    where id = p_space;
  for v_job in select id from public.jobs where space_id = p_space and alert_settings is null
      and status::text in ('scheduled', 'confirmed', 'on_the_way', 'working') loop
    perform public.schedule_job_reminders(v_job);
  end loop;
end $$;
revoke execute on function public.set_space_alerts(uuid, jsonb) from public, anon;
grant execute on function public.set_space_alerts(uuid, jsonb) to authenticated;

-- A phone belongs to whoever signed in last. Before, the second person on a
-- phone was refused and the first one kept getting the alerts.
create or replace function public.register_device(p_token text, p_platform text, p_version text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if length(coalesce(p_token, '')) < 10 then
    raise exception 'Not a phone token' using errcode = 'check_violation';
  end if;
  insert into public.devices(user_id, fcm_token, platform, app_version, last_seen_at)
    values (auth.uid(), p_token, p_platform, p_version, now())
    on conflict (fcm_token) do update set user_id = excluded.user_id, platform = excluded.platform,
      app_version = excluded.app_version, last_seen_at = now();
end $$;
revoke execute on function public.register_device(text, text, text) from public, anon;
grant execute on function public.register_device(text, text, text) to authenticated;
