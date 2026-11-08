-- Phase 2: groups. Activity feed, per member breakdown, invite preview, leave.

-- Activity feed: entries and membership changes in one list, newest first.
create view public.activity_feed with (security_invoker = true) as
  select e.space_id,
         e.created_at as at,
         case when e.source_type = 'reversal' then 'entry_cancelled' else 'entry_added' end as kind,
         e.created_by as actor_id,
         pr.display_name as actor_name,
         pa.name as party_name,
         e.amount_paisa,
         e.direction::text as direction,
         e.id as entry_id,
         e.party_id,
         e.note
  from public.entries e
  join public.parties pa on pa.id = e.party_id
  left join public.profiles pr on pr.user_id = e.created_by
  union all
  select m.space_id,
         m.joined_at as at,
         'member_joined' as kind,
         m.user_id as actor_id,
         pr.display_name as actor_name,
         null, null, null, null, null, null
  from public.space_members m
  left join public.profiles pr on pr.user_id = m.user_id;

-- Per member totals: how much each person recorded.
create view public.space_member_stats with (security_invoker = true) as
  select m.space_id, m.user_id, pr.display_name, m.role, m.joined_at,
         count(e.id) filter (where e.voided_at is null and e.source_type <> 'reversal')::int as entries_count,
         coalesce(sum(e.amount_paisa) filter (where e.direction = 'gave' and e.voided_at is null and e.source_type <> 'reversal'), 0)::bigint as gave_paisa,
         coalesce(sum(e.amount_paisa) filter (where e.direction = 'got' and e.voided_at is null and e.source_type <> 'reversal'), 0)::bigint as got_paisa,
         max(e.created_at) as last_entry_at
  from public.space_members m
  left join public.profiles pr on pr.user_id = m.user_id
  left join public.entries e on e.space_id = m.space_id and e.created_by = m.user_id
  group by m.space_id, m.user_id, pr.display_name, m.role, m.joined_at;

grant select on public.activity_feed, public.space_member_stats to authenticated;

-- What an invite link leads to, shown before the person accepts. The token
-- itself is the secret, so knowing it is enough to see the space name.
create or replace function public.invite_preview(p_token text)
returns table (space_name text, inviter_name text, role public.member_role, expires_at timestamptz, valid boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_hash text;
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  v_hash := encode(digest(p_token, 'sha256'), 'hex');
  return query
    select s.name, pr.display_name, i.role, i.expires_at,
           (i.used_at is null and i.expires_at > now()) as valid
    from public.invites i
    join public.spaces s on s.id = i.space_id
    left join public.profiles pr on pr.user_id = i.created_by
    where i.token_hash = v_hash;
end $$;
revoke execute on function public.invite_preview(text) from public, anon;
grant execute on function public.invite_preview(text) to authenticated;

-- Leave a space. The last owner cannot leave (trigger), and the personal space cannot be left.
create or replace function public.leave_space(p_space uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if (select kind from public.spaces where id = p_space) = 'personal' then
    raise exception 'You cannot leave your personal space' using errcode = 'check_violation';
  end if;
  delete from public.space_members where space_id = p_space and user_id = auth.uid();
end $$;
revoke execute on function public.leave_space(uuid) from public, anon;
grant execute on function public.leave_space(uuid) to authenticated;

-- Index to speed up the feed.
create index if not exists entries_space_created_idx on public.entries(space_id, created_at desc);
