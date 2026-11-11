-- "Book another visit". After a job is done (even billed and paid) the
-- customer may ask for more work. The installer on the job or an owner or
-- manager books a new visit: a new job for the same customer, address and
-- team at a new time, with its own bill later. The new job remembers which
-- job it came from, and managers are alerted.

alter table public.jobs
  add column follow_up_of uuid references public.jobs(id) on delete set null;
create index jobs_follow_up_of_idx on public.jobs(follow_up_of);

create or replace function public.book_follow_up(
  p_job uuid,
  p_scheduled_at timestamptz,
  p_title text default null,
  p_notes text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  j public.jobs%rowtype;
  v_job uuid;
  v_title text;
  u uuid;
begin
  select * into j from public.jobs where id = p_job;
  if not found then raise exception 'Job not found' using errcode = 'P0002'; end if;
  if not (public.has_role_at_least(j.space_id, 'manager') or public.is_job_assignee(p_job)) then
    raise exception 'You are not on this job' using errcode = '42501';
  end if;
  if p_scheduled_at is null then
    raise exception 'Pick a date for the visit' using errcode = 'check_violation';
  end if;
  v_title := coalesce(nullif(btrim(coalesce(p_title, '')), ''), j.title);
  insert into public.jobs(space_id, customer_id, title, job_type, scheduled_at, address, geo_lat, geo_lng,
                          notes, created_by, follow_up_of)
    values (j.space_id, j.customer_id, left(v_title, 200), j.job_type, p_scheduled_at, j.address, j.geo_lat, j.geo_lng,
            coalesce(nullif(btrim(coalesce(p_notes, '')), ''), j.notes), auth.uid(), p_job)
    returning id into v_job;
  insert into public.job_events(job_id, space_id, event_type, to_status, actor_id, note)
    values (v_job, j.space_id, 'created', 'scheduled', auth.uid(), 'follow up of ' || p_job::text);
  -- The same team goes again; if nobody was on the first job, whoever books it.
  for u in select user_id from public.job_assignees where job_id = p_job loop
    insert into public.job_assignees(job_id, user_id, space_id) values (v_job, u, j.space_id) on conflict do nothing;
  end loop;
  if not exists (select 1 from public.job_assignees where job_id = v_job) then
    insert into public.job_assignees(job_id, user_id, space_id) values (v_job, auth.uid(), j.space_id);
  end if;
  insert into public.job_events(job_id, space_id, event_type, actor_id, note)
    values (p_job, j.space_id, 'follow_up', auth.uid(), v_job::text);
  perform public.notify_now(j.space_id, 'job_status', v_job, public.space_managers(j.space_id),
    jsonb_build_object('job_id', v_job, 'title', v_title, 'status', 'follow_up', 'scheduled_at', p_scheduled_at,
                       'actor_id', auth.uid(), 'space_id', j.space_id));
  perform public.schedule_job_alerts(v_job);
  return v_job;
end $$;
revoke execute on function public.book_follow_up(uuid, timestamptz, text, text) from public, anon;
grant execute on function public.book_follow_up(uuid, timestamptz, text, text) to authenticated;

-- Fix: setting up a job's reminders used to cancel every unsent alert for
-- the job, including the one written a moment before. So "job finished",
-- "job moved", "job cancelled" and "another visit booked" were cancelled
-- before they could be sent. Now only the reminders themselves are reset.
create or replace function public.schedule_job_alerts(p_job uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  j public.jobs%rowtype;
  v_assignees uuid[];
  v_managers uuid[];
  v_payload jsonb;
begin
  select * into j from public.jobs where id = p_job;
  -- Drop the reminders still pending for this job; they are recomputed
  -- below. Only these four kinds: status, moved, cancelled and new visit
  -- alerts written just before this call must still go out.
  update public.scheduled_notifications set cancelled_at = now()
    where job_id = p_job and sent_at is null and cancelled_at is null
      and kind in ('job_assigned', 'job_unconfirmed', 'jobs_tomorrow', 'job_soon');
  if j.status in ('cancelled', 'finished', 'invoiced', 'paid') then return; end if;
  v_assignees := public.job_assignee_ids(p_job);
  v_managers := public.space_managers(j.space_id);
  v_payload := jsonb_build_object('job_id', j.id, 'title', j.title, 'scheduled_at', j.scheduled_at,
                                  'customer_id', j.customer_id, 'space_id', j.space_id);
  if array_length(v_assignees, 1) is null then return; end if;
  -- Right away: you have a job.
  insert into public.scheduled_notifications(space_id, kind, due_at, job_id, recipients, payload)
    values (j.space_id, 'job_assigned', now(), j.id, v_assignees, v_payload);
  -- 30 minutes later: nobody confirmed (skipped at send time if someone did).
  insert into public.scheduled_notifications(space_id, kind, due_at, job_id, recipients, payload)
    values (j.space_id, 'job_unconfirmed', now() + interval '30 minutes', j.id, v_assignees || v_managers, v_payload);
  -- Evening before.
  if public.evening_before(j.scheduled_at) > now() then
    insert into public.scheduled_notifications(space_id, kind, due_at, job_id, recipients, payload)
      values (j.space_id, 'jobs_tomorrow', public.evening_before(j.scheduled_at), j.id, v_assignees || v_managers, v_payload);
  end if;
  -- One hour before.
  if j.scheduled_at - interval '1 hour' > now() then
    insert into public.scheduled_notifications(space_id, kind, due_at, job_id, recipients, payload)
      values (j.space_id, 'job_soon', j.scheduled_at - interval '1 hour', j.id, v_assignees, v_payload);
  end if;
end $$;
