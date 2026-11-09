-- Client error reports.
--
-- When something fails on a phone the app shows "Something went wrong" and
-- the cause stays on the phone. This table lets the app drop a short report
-- so the cause can be read from the database instead of from a screenshot.
--
-- A signed in user may add reports about themself and nothing else: no
-- reading, changing or deleting, not even of their own rows. Reports are read
-- from the dashboard or with the service role.

create table public.client_errors (
  id           bigint generated always as identity primary key,
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  source       text not null check (source in ('flutter', 'platform', 'provider')),
  message      text not null check (char_length(message) between 1 and 2000),
  detail       text check (detail is null or char_length(detail) <= 8000),
  screen       text check (screen is null or char_length(screen) <= 200),
  app_version  text check (app_version is null or char_length(app_version) <= 40),
  platform     text check (platform is null or char_length(platform) <= 20),
  created_at   timestamptz not null default now()
);
create index client_errors_created_idx on public.client_errors(created_at desc);
create index client_errors_user_idx on public.client_errors(user_id);

alter table public.client_errors enable row level security;

create policy client_errors_insert_own on public.client_errors for insert
  to authenticated
  with check (user_id = (select auth.uid()));

-- Supabase grants every right on new tables by default. Take them all back
-- and hand out insert alone, so there is no read path even if a select
-- policy is added by mistake later.
revoke all on public.client_errors from public, anon, authenticated;
grant insert on public.client_errors to authenticated;
