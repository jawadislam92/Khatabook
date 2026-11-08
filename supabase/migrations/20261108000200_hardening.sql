-- Hardening from the Supabase security and performance advisors.
-- 1. Trigger and helper functions must not be callable through the API.
-- 2. Public RPCs are for signed in users only, never anonymous.
-- 3. Every function pins search_path.
-- 4. auth.uid() in policies is wrapped in a sub select so it is evaluated once per query.
-- 5. Indexes on foreign keys the advisor flagged.

-- Trigger functions: nobody calls these directly.
revoke execute on function public.audit_row() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.protect_last_owner() from public, anon, authenticated;
revoke execute on function public.set_updated_at() from public, anon, authenticated;

-- Policy helpers: policies run as the calling user, so authenticated keeps execute.
-- They only ever answer "is this user a member", which the user may know. Anonymous
-- callers have no user id, so nothing to answer.
revoke execute on function public.member_role_in(uuid) from public, anon;
revoke execute on function public.is_member(uuid) from public, anon;
revoke execute on function public.has_role_at_least(uuid, public.member_role) from public, anon;
revoke execute on function public.role_rank(public.member_role) from public, anon;

-- RPCs: signed in users only.
revoke execute on function public.create_space(text, boolean) from public, anon;
revoke execute on function public.create_invite(uuid, public.member_role, text) from public, anon;
revoke execute on function public.accept_invite(text) from public, anon;

-- Pin search_path everywhere.
alter function public.set_updated_at() set search_path = public;
alter function public.role_rank(public.member_role) set search_path = public;
alter function public.protect_last_owner() set search_path = public;

-- Policies: evaluate auth.uid() once per statement.
drop policy profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
  using (
    user_id = (select auth.uid())
    or exists (
      select 1 from public.space_members a
      join public.space_members b on a.space_id = b.space_id
      where a.user_id = (select auth.uid()) and b.user_id = profiles.user_id
    )
  );
drop policy profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy space_members_delete on public.space_members;
create policy space_members_delete on public.space_members for delete
  using (
    user_id = (select auth.uid())
    or public.has_role_at_least(space_id, 'owner')
    or (public.has_role_at_least(space_id, 'manager') and role in ('member', 'viewer'))
  );
drop policy devices_all_own on public.devices;
create policy devices_all_own on public.devices for all
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Foreign key indexes.
create index if not exists invites_created_by_idx on public.invites(created_by);
create index if not exists invites_used_by_idx on public.invites(used_by) where used_by is not null;
create index if not exists spaces_created_by_idx on public.spaces(created_by);

-- Future tables and functions: do not hand execute to anon by default.
alter default privileges in schema public revoke execute on functions from public, anon;
