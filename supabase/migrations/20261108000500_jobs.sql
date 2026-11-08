-- Phase 3: business. Item catalog, jobs, assignment, status history, and the
-- notification scheduler. Push delivery itself is an Edge Function that reads
-- scheduled_notifications every minute.

create type public.job_type as enum ('cctv_install', 'cctv_repair', 'solar_install', 'solar_service', 'other');
create type public.job_status as enum ('scheduled', 'confirmed', 'on_the_way', 'working', 'finished', 'invoiced', 'paid', 'cancelled');
create type public.notification_kind as enum (
  'job_assigned', 'job_unconfirmed', 'jobs_tomorrow', 'job_soon', 'job_status', 'job_rescheduled', 'job_cancelled',
  'entry_added', 'reminder_due', 'invoice_issued', 'payment_received');

-- ---------------------------------------------------------------------------
-- item catalog
-- ---------------------------------------------------------------------------
create table public.items (
  id                uuid primary key default gen_random_uuid(),
  space_id          uuid not null references public.spaces(id) on delete cascade,
  name_en           text not null check (char_length(name_en) between 1 and 120),
  name_ur           text,
  unit              text not null default 'pc',
  category          text not null default 'other',
  sale_price_paisa  bigint not null check (sale_price_paisa >= 0),
  cost_price_paisa  bigint check (cost_price_paisa is null or cost_price_paisa >= 0),
  is_favourite      boolean not null default false,
  allow_price_edit  boolean not null default false,
  active            boolean not null default true,
  sort_order        int not null default 0,
  created_by        uuid not null references auth.users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index items_space_idx on public.items(space_id) where active;
create index items_created_by_idx on public.items(created_by);
create trigger items_updated_at before update on public.items for each row execute function public.set_updated_at();
create trigger audit_items after insert or update or delete on public.items for each row execute function public.audit_row();

-- Whether the caller may see cost prices in a space: owner always, manager if the space allows.
create or replace function public.can_see_costs(p_space uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_role_at_least(p_space, 'owner')
      or (public.has_role_at_least(p_space, 'manager')
          and coalesce((select (settings->>'managers_see_costs')::boolean from public.spaces where id = p_space), false))
$$;
revoke execute on function public.can_see_costs(uuid) from public, anon;
grant execute on function public.can_see_costs(uuid) to authenticated;

-- The app reads items through this view so cost prices never reach installers.
-- It runs as its owner on purpose: an invoker view would require the reader to
-- have access to the hidden column. Membership is checked inside the view and
-- security_barrier stops leaky predicates from seeing rows first.
create view public.items_visible with (security_barrier = true) as
  select id, space_id, name_en, name_ur, unit, category, sale_price_paisa,
         case when public.can_see_costs(space_id) then cost_price_paisa end as cost_price_paisa,
         is_favourite, allow_price_edit, active, sort_order, created_at, updated_at
  from public.items
  where public.is_member(space_id);

-- ---------------------------------------------------------------------------
-- jobs
-- ---------------------------------------------------------------------------
create table public.jobs (
  id              uuid primary key default gen_random_uuid(),
  space_id        uuid not null references public.spaces(id) on delete cascade,
  customer_id     uuid not null references public.parties(id),
  title           text not null check (char_length(title) between 1 and 200),
  job_type        public.job_type not null default 'other',
  scheduled_at    timestamptz not null,
  address         text,
  geo_lat         double precision,
  geo_lng         double precision,
  notes           text,
  estimate_paisa  bigint check (estimate_paisa is null or estimate_paisa >= 0),
  status          public.job_status not null default 'scheduled',
  created_by      uuid not null references auth.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index jobs_space_sched_idx on public.jobs(space_id, scheduled_at);
create index jobs_customer_idx on public.jobs(customer_id);
create index jobs_created_by_idx on public.jobs(created_by);
create trigger jobs_updated_at before update on public.jobs for each row execute function public.set_updated_at();
create trigger audit_jobs after insert or update or delete on public.jobs for each row execute function public.audit_row();

create table public.job_assignees (
  job_id        uuid not null references public.jobs(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  space_id      uuid not null references public.spaces(id) on delete cascade,
  assigned_at   timestamptz not null default now(),
  confirmed_at  timestamptz,
  primary key (job_id, user_id)
);
create index job_assignees_user_idx on public.job_assignees(user_id);
create index job_assignees_space_idx on public.job_assignees(space_id);

create table public.job_events (
  id           bigint generated always as identity primary key,
  job_id       uuid not null references public.jobs(id) on delete cascade,
  space_id     uuid not null references public.spaces(id) on delete cascade,
  event_type   text not null,          -- created, assigned, unassigned, confirmed, status, rescheduled, note
  from_status  public.job_status,
  to_status    public.job_status,
  actor_id     uuid references auth.users(id),
  note         text,
  at           timestamptz not null default now()
);
create index job_events_job_idx on public.job_events(job_id, at);
create index job_events_actor_idx on public.job_events(actor_id);

create table public.job_photos (
  id            uuid primary key default gen_random_uuid(),
  job_id        uuid not null references public.jobs(id) on delete cascade,
  space_id      uuid not null references public.spaces(id) on delete cascade,
  storage_path  text not null,
  kind          text not null default 'after' check (kind in ('before', 'after', 'other')),
  created_by    uuid not null references auth.users(id),
  created_at    timestamptz not null default now()
);
create index job_photos_job_idx on public.job_photos(job_id);
create index job_photos_created_by_idx on public.job_photos(created_by);

-- Materials and labour used. Filled at Finish. Price is a snapshot of the catalog price.
create table public.job_items (
  id                uuid primary key default gen_random_uuid(),
  job_id            uuid not null references public.jobs(id) on delete cascade,
  space_id          uuid not null references public.spaces(id) on delete cascade,
  item_id           uuid references public.items(id),
  description       text not null,
  qty               numeric(12,3) not null check (qty > 0),
  unit_price_paisa  bigint not null check (unit_price_paisa >= 0),
  note              text,
  created_by        uuid not null references auth.users(id),
  created_at        timestamptz not null default now()
);
create index job_items_job_idx on public.job_items(job_id);
create index job_items_item_idx on public.job_items(item_id);
create index job_items_created_by_idx on public.job_items(created_by);

-- ---------------------------------------------------------------------------
-- notifications
-- ---------------------------------------------------------------------------
create table public.scheduled_notifications (
  id            uuid primary key default gen_random_uuid(),
  space_id      uuid not null references public.spaces(id) on delete cascade,
  kind          public.notification_kind not null,
  due_at        timestamptz not null,
  job_id        uuid references public.jobs(id) on delete cascade,
  recipients    uuid[] not null,
  payload       jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  sent_at       timestamptz,
  cancelled_at  timestamptz,
  attempts      int not null default 0,
  last_error    text
);
create index scheduled_notifications_due_idx on public.scheduled_notifications(due_at) where sent_at is null and cancelled_at is null;
create index scheduled_notifications_job_idx on public.scheduled_notifications(job_id);
create index scheduled_notifications_space_idx on public.scheduled_notifications(space_id);

-- In app inbox, one row per recipient.
create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  space_id    uuid references public.spaces(id) on delete cascade,
  kind        public.notification_kind not null,
  title       text not null,
  body        text not null,
  deep_link   text,
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);
create index notifications_user_idx on public.notifications(user_id, created_at desc);
create index notifications_space_idx on public.notifications(space_id);

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
create or replace function public.space_managers(p_space uuid)
returns uuid[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(user_id), '{}') from public.space_members
  where space_id = p_space and role in ('owner', 'manager')
$$;
revoke execute on function public.space_managers(uuid) from public, anon, authenticated;

create or replace function public.job_assignee_ids(p_job uuid)
returns uuid[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(user_id), '{}') from public.job_assignees where job_id = p_job
$$;
revoke execute on function public.job_assignee_ids(uuid) from public, anon, authenticated;

create or replace function public.is_job_assignee(p_job uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.job_assignees where job_id = p_job and user_id = auth.uid())
$$;
revoke execute on function public.is_job_assignee(uuid) from public, anon;
grant execute on function public.is_job_assignee(uuid) to authenticated;

-- Evening before at 20:00 Pakistan time.
create or replace function public.evening_before(p_at timestamptz)
returns timestamptz language sql immutable set search_path = public as $$
  select ((p_at at time zone 'Asia/Karachi')::date - 1 + time '20:00') at time zone 'Asia/Karachi'
$$;
revoke execute on function public.evening_before(timestamptz) from public, anon, authenticated;

-- (Re)build the pending alert rows for a job. Called after create, assign, reschedule.
create or replace function public.schedule_job_alerts(p_job uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  j public.jobs%rowtype;
  v_assignees uuid[];
  v_managers uuid[];
  v_payload jsonb;
begin
  select * into j from public.jobs where id = p_job;
  -- Drop anything still pending for this job; it is recomputed below.
  update public.scheduled_notifications set cancelled_at = now()
    where job_id = p_job and sent_at is null and cancelled_at is null;
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
revoke execute on function public.schedule_job_alerts(uuid) from public, anon, authenticated;

-- Immediate notice to a set of people (sent by the next cron tick).
create or replace function public.notify_now(p_space uuid, p_kind public.notification_kind, p_job uuid, p_recipients uuid[], p_payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if array_length(p_recipients, 1) is null then return; end if;
  insert into public.scheduled_notifications(space_id, kind, due_at, job_id, recipients, payload)
    values (p_space, p_kind, now(), p_job, p_recipients, p_payload);
end $$;
revoke execute on function public.notify_now(uuid, public.notification_kind, uuid, uuid[], jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- job lifecycle functions (the app uses these, never raw updates for status)
-- ---------------------------------------------------------------------------
create or replace function public.create_job(
  p_space uuid, p_customer uuid, p_title text, p_type public.job_type, p_scheduled_at timestamptz,
  p_assignees uuid[], p_address text default null, p_notes text default null, p_estimate_paisa bigint default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_job uuid;
  u uuid;
begin
  if not public.has_role_at_least(p_space, 'manager') then
    raise exception 'Only an owner or manager can create jobs' using errcode = '42501';
  end if;
  if not exists (select 1 from public.parties where id = p_customer and space_id = p_space and deleted_at is null) then
    raise exception 'Customer not in this space' using errcode = 'check_violation';
  end if;
  insert into public.jobs(space_id, customer_id, title, job_type, scheduled_at, address, notes, estimate_paisa, created_by)
    values (p_space, p_customer, p_title, p_type, p_scheduled_at, p_address, p_notes, p_estimate_paisa, auth.uid())
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
revoke execute on function public.create_job(uuid, uuid, text, public.job_type, timestamptz, uuid[], text, text, bigint) from public, anon;
grant execute on function public.create_job(uuid, uuid, text, public.job_type, timestamptz, uuid[], text, text, bigint) to authenticated;

create or replace function public.set_job_assignees(p_job uuid, p_assignees uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare
  j public.jobs%rowtype;
  u uuid;
begin
  select * into j from public.jobs where id = p_job;
  if not public.has_role_at_least(j.space_id, 'manager') then
    raise exception 'Only an owner or manager can assign jobs' using errcode = '42501';
  end if;
  delete from public.job_assignees where job_id = p_job and not (user_id = any(coalesce(p_assignees, '{}')));
  foreach u in array coalesce(p_assignees, '{}') loop
    if exists (select 1 from public.space_members where space_id = j.space_id and user_id = u) then
      insert into public.job_assignees(job_id, user_id, space_id) values (p_job, u, j.space_id) on conflict do nothing;
    end if;
  end loop;
  insert into public.job_events(job_id, space_id, event_type, actor_id) values (p_job, j.space_id, 'assigned', auth.uid());
  perform public.schedule_job_alerts(p_job);
end $$;
revoke execute on function public.set_job_assignees(uuid, uuid[]) from public, anon;
grant execute on function public.set_job_assignees(uuid, uuid[]) to authenticated;

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
    status = case when status in ('confirmed', 'on_the_way') then 'scheduled' else status end
    where id = p_job;
  update public.job_assignees set confirmed_at = null where job_id = p_job;
  insert into public.job_events(job_id, space_id, event_type, actor_id, note)
    values (p_job, j.space_id, 'rescheduled', auth.uid(), coalesce(p_note, '') || ' -> ' || p_scheduled_at::text);
  perform public.notify_now(j.space_id, 'job_rescheduled', p_job, public.job_assignee_ids(p_job) || public.space_managers(j.space_id),
    jsonb_build_object('job_id', j.id, 'title', j.title, 'scheduled_at', p_scheduled_at, 'space_id', j.space_id));
  perform public.schedule_job_alerts(p_job);
end $$;
revoke execute on function public.reschedule_job(uuid, timestamptz, text) from public, anon;
grant execute on function public.reschedule_job(uuid, timestamptz, text) to authenticated;

create or replace function public.confirm_job(p_job uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  j public.jobs%rowtype;
begin
  select * into j from public.jobs where id = p_job;
  if not public.is_job_assignee(p_job) then
    raise exception 'Only an assigned person can confirm' using errcode = '42501';
  end if;
  update public.job_assignees set confirmed_at = now() where job_id = p_job and user_id = auth.uid() and confirmed_at is null;
  if j.status = 'scheduled' then
    update public.jobs set status = 'confirmed' where id = p_job;
    insert into public.job_events(job_id, space_id, event_type, from_status, to_status, actor_id)
      values (p_job, j.space_id, 'confirmed', 'scheduled', 'confirmed', auth.uid());
    -- The unconfirmed nag is no longer needed.
    update public.scheduled_notifications set cancelled_at = now()
      where job_id = p_job and kind = 'job_unconfirmed' and sent_at is null and cancelled_at is null;
    perform public.notify_now(j.space_id, 'job_status', p_job, public.space_managers(j.space_id),
      jsonb_build_object('job_id', j.id, 'title', j.title, 'status', 'confirmed', 'actor_id', auth.uid(), 'space_id', j.space_id));
  end if;
end $$;
revoke execute on function public.confirm_job(uuid) from public, anon;
grant execute on function public.confirm_job(uuid) to authenticated;

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
  if p_status = 'cancelled' and not v_manager then
    raise exception 'Only an owner or manager can cancel a job' using errcode = '42501';
  end if;
  if j.status in ('invoiced', 'paid') then
    raise exception 'This job is already invoiced' using errcode = 'check_violation';
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
revoke execute on function public.set_job_status(uuid, public.job_status, text) from public, anon;
grant execute on function public.set_job_status(uuid, public.job_status, text) to authenticated;

-- Called by the Edge Function with the service role after a push is sent, to fill the inbox.
create or replace function public.mark_notification_sent(p_id uuid, p_title text, p_body text, p_deep_link text, p_error text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  n public.scheduled_notifications%rowtype;
  u uuid;
begin
  select * into n from public.scheduled_notifications where id = p_id for update;
  if p_error is not null then
    update public.scheduled_notifications set attempts = attempts + 1, last_error = p_error,
      sent_at = case when attempts + 1 >= 5 then now() else null end where id = p_id;
    return;
  end if;
  update public.scheduled_notifications set sent_at = now(), attempts = attempts + 1 where id = p_id;
  foreach u in array n.recipients loop
    insert into public.notifications(user_id, space_id, kind, title, body, deep_link)
      values (u, n.space_id, n.kind, p_title, p_body, p_deep_link);
  end loop;
end $$;
revoke execute on function public.mark_notification_sent(uuid, text, text, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.items enable row level security;
alter table public.jobs enable row level security;
alter table public.job_assignees enable row level security;
alter table public.job_events enable row level security;
alter table public.job_photos enable row level security;
alter table public.job_items enable row level security;
alter table public.scheduled_notifications enable row level security;
alter table public.notifications enable row level security;

-- items: members read through the view (which hides cost); managers manage.
create policy items_select on public.items for select using (public.is_member(space_id));
create policy items_insert on public.items for insert
  with check (public.has_role_at_least(space_id, 'manager') and created_by = (select auth.uid()));
create policy items_update on public.items for update
  using (public.has_role_at_least(space_id, 'manager')) with check (public.has_role_at_least(space_id, 'manager'));
-- Direct table reads would expose cost_price_paisa, so the base table is not granted; only the view is.
revoke all on public.items from authenticated;
grant select on public.items_visible to authenticated;
grant insert, update on public.items to authenticated;
-- insert/update need select for RETURNING: grant select on non cost columns only.
grant select (id, space_id, name_en, name_ur, unit, category, sale_price_paisa, is_favourite, allow_price_edit, active, sort_order, created_by, created_at, updated_at) on public.items to authenticated;

-- jobs: members see all jobs in the space; writes go through functions, except details edits by managers.
create policy jobs_select on public.jobs for select using (public.is_member(space_id));
create policy jobs_update on public.jobs for update
  using (public.has_role_at_least(space_id, 'manager')) with check (public.has_role_at_least(space_id, 'manager'));
grant select, update (title, job_type, address, geo_lat, geo_lng, notes, estimate_paisa, customer_id) on public.jobs to authenticated;

create policy job_assignees_select on public.job_assignees for select using (public.is_member(space_id));
grant select on public.job_assignees to authenticated;

create policy job_events_select on public.job_events for select using (public.is_member(space_id));
create policy job_events_insert on public.job_events for insert
  with check (public.is_member(space_id) and event_type = 'note' and actor_id = (select auth.uid()));
grant select, insert on public.job_events to authenticated;
grant usage, select on sequence public.job_events_id_seq to authenticated;

create policy job_photos_select on public.job_photos for select using (public.is_member(space_id));
create policy job_photos_insert on public.job_photos for insert
  with check ((public.has_role_at_least(space_id, 'manager') or public.is_job_assignee(job_id)) and created_by = (select auth.uid()));
create policy job_photos_delete on public.job_photos for delete
  using (public.has_role_at_least(space_id, 'manager') or created_by = (select auth.uid()));
grant select, insert, delete on public.job_photos to authenticated;

create policy job_items_select on public.job_items for select using (public.is_member(space_id));
create policy job_items_write on public.job_items for all
  using (public.has_role_at_least(space_id, 'manager') or public.is_job_assignee(job_id))
  with check ((public.has_role_at_least(space_id, 'manager') or public.is_job_assignee(job_id)) and created_by = (select auth.uid()));
grant select, insert, update, delete on public.job_items to authenticated;

create policy scheduled_notifications_select on public.scheduled_notifications for select
  using (public.has_role_at_least(space_id, 'manager'));
grant select on public.scheduled_notifications to authenticated;

create policy notifications_own on public.notifications for select using (user_id = (select auth.uid()));
create policy notifications_read on public.notifications for update
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
grant select, update (read_at) on public.notifications to authenticated;

-- A job cannot be voided through the generic path; and job_items on invoiced jobs are frozen.
create or replace function public.check_job_items()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_status public.job_status;
begin
  select status into v_status from public.jobs where id = coalesce(new.job_id, old.job_id);
  if v_status in ('invoiced', 'paid') then
    raise exception 'This job is invoiced; its items are frozen' using errcode = 'check_violation';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
revoke execute on function public.check_job_items() from public, anon, authenticated;
create trigger job_items_check before insert or update or delete on public.job_items
  for each row execute function public.check_job_items();
