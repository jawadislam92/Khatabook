-- The owner can delete a whole group. It disappears for everyone at once:
-- every policy and RPC asks these helpers, and a deleted space has no members
-- as far as they are concerned. The rows stay (entries are never erased), so a
-- mistake can be put right by the operator:
--   update public.spaces set deleted_at = null where id = '<space>';

create or replace function public.member_role_in(p_space uuid)
returns public.member_role
language sql stable security definer set search_path = public as $$
  select m.role from public.space_members m
  join public.spaces s on s.id = m.space_id
  where m.space_id = p_space and m.user_id = auth.uid() and s.deleted_at is null
$$;

create or replace function public.is_member(p_space uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.space_members m
    join public.spaces s on s.id = m.space_id
    where m.space_id = p_space and m.user_id = auth.uid() and s.deleted_at is null
  )
$$;

create or replace function public.is_job_assignee(p_job uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.job_assignees a
    join public.spaces s on s.id = a.space_id
    where a.job_id = p_job and a.user_id = auth.uid() and s.deleted_at is null
  )
$$;

create or replace function public.delete_space(p_space uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.has_role_at_least(p_space, 'owner') then
    raise exception 'Only the owner can delete a group' using errcode = '42501';
  end if;
  if (select kind from public.spaces where id = p_space) = 'personal' then
    raise exception 'You cannot delete your personal space' using errcode = 'check_violation';
  end if;
  -- No alert, inbox row or open invite may lead into a deleted group.
  update public.scheduled_notifications set cancelled_at = now()
    where space_id = p_space and sent_at is null and cancelled_at is null;
  delete from public.notifications where space_id = p_space;
  delete from public.invites where space_id = p_space and used_at is null;
  update public.spaces set deleted_at = now() where id = p_space;
end $$;
revoke execute on function public.delete_space(uuid) from public, anon;
grant execute on function public.delete_space(uuid) to authenticated;
