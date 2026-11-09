-- Profile links and live updates.
--
-- The app shows who recorded an entry, who moved a job and who is assigned to
-- it by asking the API to attach profiles through these columns. The API only
-- follows foreign keys inside the public schema, and these columns pointed at
-- auth.users, so every such request failed with PGRST200 and the app showed
-- "Something went wrong" or spun forever. Each column keeps its auth.users key
-- and gains one to profiles with the same delete behaviour. A profile exists
-- for every user from the moment they sign up (handle_new_user).

alter table public.entries
  add constraint entries_created_by_profile_fkey
  foreign key (created_by) references public.profiles(user_id);

alter table public.job_events
  add constraint job_events_actor_id_profile_fkey
  foreign key (actor_id) references public.profiles(user_id);

alter table public.job_assignees
  add constraint job_assignees_user_id_profile_fkey
  foreign key (user_id) references public.profiles(user_id) on delete cascade;

-- Live updates. The app listens for changes on these tables. A new project
-- ships the supabase_realtime publication empty, so nothing was ever sent and
-- screens only refreshed when reopened. Row level security still decides what
-- each listener receives.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime
      add table public.entries, public.parties, public.jobs, public.job_assignees, public.invoices;
  end if;
end $$;
