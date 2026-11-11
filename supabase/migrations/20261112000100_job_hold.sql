-- "Can't finish today". The installer on site can stop a job for a reason
-- (no electricity, customer away, parts missing, weather, other), all of it
-- optional, and suggest a date. The job then waits as "Needs new date"
-- (status on_hold) until an owner or manager sets the new date.
--
-- Nothing here blocks the journey: reason, note and date are optional, and
-- reschedule now also brings a job back from working or on hold.

alter type public.job_status add value if not exists 'on_hold' after 'working';

alter table public.jobs
  add column hold_reason  text check (hold_reason is null or hold_reason in
                            ('no_power', 'customer_away', 'parts_missing', 'weather', 'other')),
  add column hold_note    text check (hold_note is null or char_length(hold_note) <= 500),
  add column suggested_at timestamptz;

create or replace function public.report_job_problem(
  p_job uuid,
  p_reason text default null,
  p_note text default null,
  p_suggested_at timestamptz default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  j public.jobs%rowtype;
begin
  select * into j from public.jobs where id = p_job for update;
  if not found then raise exception 'Job not found' using errcode = 'P0002'; end if;
  if not (public.has_role_at_least(j.space_id, 'manager') or public.is_job_assignee(p_job)) then
    raise exception 'You are not on this job' using errcode = '42501';
  end if;
  if j.status::text not in ('scheduled', 'confirmed', 'on_the_way', 'working') then
    raise exception 'Only a job that is still open can be stopped' using errcode = 'check_violation';
  end if;
  update public.jobs set status = 'on_hold',
         hold_reason = nullif(p_reason, ''),
         hold_note = nullif(btrim(coalesce(p_note, '')), ''),
         suggested_at = p_suggested_at
    where id = p_job;
  insert into public.job_events(job_id, space_id, event_type, from_status, to_status, actor_id, note)
    values (p_job, j.space_id, 'on_hold', j.status, 'on_hold', auth.uid(),
            concat_ws(' | ', nullif(p_reason, ''), nullif(btrim(coalesce(p_note, '')), '')));
  -- Reminders for the old time no longer apply.
  update public.scheduled_notifications set cancelled_at = now()
    where job_id = p_job and sent_at is null and cancelled_at is null;
  perform public.notify_now(j.space_id, 'job_status', p_job, public.space_managers(j.space_id),
    jsonb_build_object('job_id', j.id, 'title', j.title, 'status', 'on_hold', 'reason', p_reason,
                       'suggested_at', p_suggested_at, 'actor_id', auth.uid(), 'space_id', j.space_id));
end $$;
revoke execute on function public.report_job_problem(uuid, text, text, timestamptz) from public, anon;
grant execute on function public.report_job_problem(uuid, text, text, timestamptz) to authenticated;

-- Reschedule also brings back a job that was being worked or was on hold.
create or replace function public.reschedule_job(p_job uuid, p_scheduled_at timestamptz, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  j public.jobs%rowtype;
begin
  select * into j from public.jobs where id = p_job;
  if not public.has_role_at_least(j.space_id, 'manager') then
    raise exception 'Only an owner or manager can reschedule' using errcode = '42501';
  end if;
  update public.jobs set scheduled_at = p_scheduled_at,
    status = case when status::text in ('confirmed', 'on_the_way', 'working', 'on_hold') then 'scheduled' else status end,
    hold_reason = null, hold_note = null, suggested_at = null
    where id = p_job;
  update public.job_assignees set confirmed_at = null where job_id = p_job;
  insert into public.job_events(job_id, space_id, event_type, actor_id, note)
    values (p_job, j.space_id, 'rescheduled', auth.uid(), coalesce(p_note, '') || ' -> ' || p_scheduled_at::text);
  perform public.notify_now(j.space_id, 'job_rescheduled', p_job, public.job_assignee_ids(p_job) || public.space_managers(j.space_id),
    jsonb_build_object('job_id', j.id, 'title', j.title, 'scheduled_at', p_scheduled_at, 'space_id', j.space_id));
  perform public.schedule_job_alerts(p_job);
end $$;

-- A job on hold leaves that state only by a new date or by cancelling.
create or replace function public.set_job_status(p_job uuid, p_status public.job_status, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  j public.jobs%rowtype;
  v_manager boolean;
begin
  select * into j from public.jobs where id = p_job for update;
  v_manager := public.has_role_at_least(j.space_id, 'manager');
  if not (v_manager or public.is_job_assignee(p_job)) then
    raise exception 'You are not on this job' using errcode = '42501';
  end if;
  if p_status in ('invoiced', 'paid') then
    raise exception 'Invoiced and paid are set by the invoice' using errcode = 'check_violation';
  end if;
  if p_status::text = 'on_hold' then
    raise exception 'Use report_job_problem to put a job on hold' using errcode = 'check_violation';
  end if;
  if p_status = 'cancelled' and not v_manager then
    raise exception 'Only an owner or manager can cancel a job' using errcode = '42501';
  end if;
  if j.status in ('invoiced', 'paid') then
    raise exception 'This job is already invoiced' using errcode = 'check_violation';
  end if;
  if j.status::text = 'on_hold' and p_status <> 'cancelled' then
    raise exception 'This job needs a new date first' using errcode = 'check_violation';
  end if;
  update public.jobs set status = p_status where id = p_job;
  insert into public.job_events(job_id, space_id, event_type, from_status, to_status, actor_id, note)
    values (p_job, j.space_id, 'status', j.status, p_status, auth.uid(), p_note);
  if p_status = 'cancelled' then
    perform public.notify_now(j.space_id, 'job_cancelled', p_job, public.job_assignee_ids(p_job),
      jsonb_build_object('job_id', j.id, 'title', j.title, 'space_id', j.space_id));
    perform public.schedule_job_alerts(p_job);
  elsif p_status = 'finished' then
    perform public.notify_now(j.space_id, 'job_status', p_job, public.space_managers(j.space_id),
      jsonb_build_object('job_id', j.id, 'title', j.title, 'status', p_status, 'actor_id', auth.uid(), 'space_id', j.space_id));
    perform public.schedule_job_alerts(p_job);
  else
    perform public.notify_now(j.space_id, 'job_status', p_job, public.space_managers(j.space_id),
      jsonb_build_object('job_id', j.id, 'title', j.title, 'status', p_status, 'actor_id', auth.uid(), 'space_id', j.space_id));
  end if;
end $$;
