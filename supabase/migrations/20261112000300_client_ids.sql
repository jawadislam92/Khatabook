-- Working offline. A phone with no internet makes the new job's id itself
-- and sends it later. If the answer is lost and the phone sends it again,
-- the same id comes back instead of a second job. Older app versions do not
-- send an id and keep working as before.

drop function if exists public.create_job(uuid, uuid, text, public.job_type, timestamptz, uuid[], text, text, bigint);

create function public.create_job(
  p_space uuid, p_customer uuid, p_title text, p_type public.job_type, p_scheduled_at timestamptz,
  p_assignees uuid[], p_address text default null, p_notes text default null, p_estimate_paisa bigint default null,
  p_id uuid default null)
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
  insert into public.jobs(id, space_id, customer_id, title, job_type, scheduled_at, address, notes, estimate_paisa, created_by)
    values (coalesce(p_id, gen_random_uuid()), p_space, p_customer, p_title, p_type, p_scheduled_at, p_address, p_notes,
            p_estimate_paisa, auth.uid())
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
revoke execute on function public.create_job(uuid, uuid, text, public.job_type, timestamptz, uuid[], text, text, bigint, uuid) from public, anon;
grant execute on function public.create_job(uuid, uuid, text, public.job_type, timestamptz, uuid[], text, text, bigint, uuid) to authenticated;

drop function if exists public.book_follow_up(uuid, timestamptz, text, text);

create function public.book_follow_up(
  p_job uuid,
  p_scheduled_at timestamptz,
  p_title text default null,
  p_notes text default null,
  p_id uuid default null
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
  if p_id is not null and exists (select 1 from public.jobs where id = p_id) then
    if exists (select 1 from public.jobs where id = p_id and follow_up_of = p_job) then
      return p_id; -- sent twice: the first one counted
    end if;
    raise exception 'Job id already used' using errcode = 'check_violation';
  end if;
  v_title := coalesce(nullif(btrim(coalesce(p_title, '')), ''), j.title);
  insert into public.jobs(id, space_id, customer_id, title, job_type, scheduled_at, address, geo_lat, geo_lng,
                          notes, created_by, follow_up_of)
    values (coalesce(p_id, gen_random_uuid()), j.space_id, j.customer_id, left(v_title, 200), j.job_type, p_scheduled_at,
            j.address, j.geo_lat, j.geo_lng, coalesce(nullif(btrim(coalesce(p_notes, '')), ''), j.notes), auth.uid(), p_job)
    returning id into v_job;
  insert into public.job_events(job_id, space_id, event_type, to_status, actor_id, note)
    values (v_job, j.space_id, 'created', 'scheduled', auth.uid(), 'follow up of ' || p_job::text);
  for u in select user_id from public.job_assignees where job_id = p_job loop
    insert into public.job_assignees(job_id, user_id, space_id) values (v_job, u, j.space_id) on conflict do nothing;
  end loop;
  if not exists (select 1 from public.job_assignees where job_id = v_job) then
    insert into public.job_assignees(job_id, user_id, space_id) values (v_job, auth.uid(), j.space_id);
  end if;
  insert into public.job_events(job_id, space_id, event_type, actor_id, note)
    values (p_job, j.space_id, 'follow_up', auth.uid(), v_job::text);
  perform public.schedule_job_alerts(v_job);
  perform public.notify_now(j.space_id, 'job_status', v_job, public.space_managers(j.space_id),
    jsonb_build_object('job_id', v_job, 'title', v_title, 'status', 'follow_up', 'scheduled_at', p_scheduled_at,
                       'actor_id', auth.uid(), 'space_id', j.space_id));
  return v_job;
end $$;
revoke execute on function public.book_follow_up(uuid, timestamptz, text, text, uuid) from public, anon;
grant execute on function public.book_follow_up(uuid, timestamptz, text, text, uuid) to authenticated;
