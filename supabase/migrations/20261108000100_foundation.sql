-- Phase 0 foundation: identity, spaces, membership, invites, devices, audit log.
-- Every table has Row Level Security. Policies go through the helper functions
-- at the bottom of this file so the rules live in one place.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.space_kind as enum ('personal', 'group');
create type public.member_role as enum ('owner', 'manager', 'member', 'viewer');
create type public.app_language as enum ('en', 'ur');

-- ---------------------------------------------------------------------------
-- Common helpers
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- Role rank: higher means more power. Used by the membership checks.
create or replace function public.role_rank(r public.member_role)
returns int language sql immutable as $$
  select case r
    when 'owner' then 4
    when 'manager' then 3
    when 'member' then 2
    when 'viewer' then 1
  end
$$;

-- ---------------------------------------------------------------------------
-- profiles: one row per auth user
-- ---------------------------------------------------------------------------
create table public.profiles (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  display_name   text not null check (char_length(display_name) between 1 and 80),
  phone_hash     text,                       -- sha256(salt || e164 number), for contact matching
  phone_display  text,                       -- what the user chose to show, may be null
  language       public.app_language not null default 'en',
  simple_mode    boolean not null default false,
  avatar_path    text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index profiles_phone_hash_idx on public.profiles(phone_hash) where phone_hash is not null;
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- spaces and membership
-- ---------------------------------------------------------------------------
create table public.spaces (
  id                uuid primary key default gen_random_uuid(),
  name              text not null check (char_length(name) between 1 and 80),
  kind              public.space_kind not null default 'group',
  business_enabled  boolean not null default false,
  settings          jsonb not null default '{}'::jsonb,
  created_by        uuid not null references auth.users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create trigger spaces_updated_at before update on public.spaces
  for each row execute function public.set_updated_at();

create table public.space_members (
  space_id   uuid not null references public.spaces(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       public.member_role not null default 'member',
  joined_at  timestamptz not null default now(),
  primary key (space_id, user_id)
);
create index space_members_user_idx on public.space_members(user_id);

-- Membership helpers. SECURITY DEFINER so policies can read space_members
-- without recursing into its own RLS policy.
create or replace function public.member_role_in(p_space uuid)
returns public.member_role
language sql stable security definer set search_path = public as $$
  select role from public.space_members
  where space_id = p_space and user_id = auth.uid()
$$;

create or replace function public.is_member(p_space uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.space_members
    where space_id = p_space and user_id = auth.uid()
  )
$$;

create or replace function public.has_role_at_least(p_space uuid, p_min public.member_role)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    public.role_rank(public.member_role_in(p_space)) >= public.role_rank(p_min),
    false)
$$;

-- ---------------------------------------------------------------------------
-- invites: single use, hashed token, 48 hour expiry
-- ---------------------------------------------------------------------------
create table public.invites (
  id          uuid primary key default gen_random_uuid(),
  space_id    uuid not null references public.spaces(id) on delete cascade,
  token_hash  text not null unique,
  role        public.member_role not null default 'member' check (role <> 'owner'),
  phone_hash  text,
  created_by  uuid not null references auth.users(id),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '48 hours',
  used_at     timestamptz,
  used_by     uuid references auth.users(id)
);
create index invites_space_idx on public.invites(space_id);

-- ---------------------------------------------------------------------------
-- devices: push tokens
-- ---------------------------------------------------------------------------
create table public.devices (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  fcm_token     text not null unique,
  platform      text not null check (platform in ('android', 'ios', 'web')),
  device_name   text,
  app_version   text,
  last_seen_at  timestamptz not null default now(),
  created_at    timestamptz not null default now()
);
create index devices_user_idx on public.devices(user_id);

-- ---------------------------------------------------------------------------
-- audit log: filled by triggers on sensitive tables
-- ---------------------------------------------------------------------------
create table public.audit_log (
  id          bigint generated always as identity primary key,
  table_name  text not null,
  row_id      text not null,
  action      text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  actor_id    uuid,
  old_row     jsonb,
  new_row     jsonb,
  at          timestamptz not null default now()
);
create index audit_log_row_idx on public.audit_log(table_name, row_id);
create index audit_log_at_idx on public.audit_log(at);

create or replace function public.audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_id text;
begin
  if tg_op = 'DELETE' then
    v_id := coalesce(to_jsonb(old)->>'id', to_jsonb(old)->>'user_id',
                     (to_jsonb(old)->>'space_id') || ':' || (to_jsonb(old)->>'user_id'));
    insert into public.audit_log(table_name, row_id, action, actor_id, old_row)
      values (tg_table_name, v_id, tg_op, auth.uid(), to_jsonb(old));
    return old;
  else
    v_id := coalesce(to_jsonb(new)->>'id', to_jsonb(new)->>'user_id',
                     (to_jsonb(new)->>'space_id') || ':' || (to_jsonb(new)->>'user_id'));
    insert into public.audit_log(table_name, row_id, action, actor_id, old_row, new_row)
      values (tg_table_name, v_id, tg_op, auth.uid(),
              case when tg_op = 'UPDATE' then to_jsonb(old) end, to_jsonb(new));
    return new;
  end if;
end $$;

create trigger audit_spaces after insert or update or delete on public.spaces
  for each row execute function public.audit_row();
create trigger audit_space_members after insert or update or delete on public.space_members
  for each row execute function public.audit_row();
create trigger audit_invites after insert or update or delete on public.invites
  for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- New user: create profile and personal space
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_space uuid;
  v_name text;
begin
  v_name := coalesce(nullif(new.raw_user_meta_data->>'display_name', ''),
                     nullif(new.raw_user_meta_data->>'full_name', ''),
                     split_part(coalesce(new.email, 'user'), '@', 1));
  insert into public.profiles(user_id, display_name, language)
    values (new.id, left(v_name, 80),
            case when new.raw_user_meta_data->>'language' = 'ur' then 'ur' else 'en' end::public.app_language);
  insert into public.spaces(name, kind, created_by)
    values ('Personal', 'personal', new.id) returning id into v_space;
  insert into public.space_members(space_id, user_id, role) values (v_space, new.id, 'owner');
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Create a group space. The caller becomes its owner. Direct inserts into spaces
-- are not allowed through the API, so this is the only way to make one.
create or replace function public.create_space(p_name text, p_business_enabled boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_space uuid;
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  insert into public.spaces(name, kind, business_enabled, created_by)
    values (p_name, 'group', p_business_enabled, auth.uid()) returning id into v_space;
  insert into public.space_members(space_id, user_id, role) values (v_space, auth.uid(), 'owner');
  return v_space;
end $$;

-- A space always keeps at least one owner.
create or replace function public.protect_last_owner()
returns trigger language plpgsql as $$
declare
  v_owners int;
begin
  if (tg_op = 'DELETE' and old.role = 'owner')
     or (tg_op = 'UPDATE' and old.role = 'owner' and new.role <> 'owner') then
    select count(*) into v_owners from public.space_members
      where space_id = old.space_id and role = 'owner' and user_id <> old.user_id;
    if v_owners = 0 then
      raise exception 'A space must keep at least one owner' using errcode = 'check_violation';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
create trigger space_members_last_owner before update or delete on public.space_members
  for each row execute function public.protect_last_owner();

-- ---------------------------------------------------------------------------
-- Accept an invite. Runs with definer rights, validates everything itself.
-- ---------------------------------------------------------------------------
create or replace function public.accept_invite(p_token text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invites%rowtype;
  v_hash text;
  v_my_phone text;
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  v_hash := encode(digest(p_token, 'sha256'), 'hex');
  select * into v_inv from public.invites where token_hash = v_hash for update;
  if not found or v_inv.used_at is not null or v_inv.expires_at < now() then
    raise exception 'This invite link is not valid any more' using errcode = 'P0001';
  end if;
  if v_inv.phone_hash is not null then
    select phone_hash into v_my_phone from public.profiles where user_id = auth.uid();
    if v_my_phone is distinct from v_inv.phone_hash then
      raise exception 'This invite was sent to a different phone number' using errcode = 'P0001';
    end if;
  end if;
  insert into public.space_members(space_id, user_id, role)
    values (v_inv.space_id, auth.uid(), v_inv.role)
    on conflict (space_id, user_id) do nothing;
  update public.invites set used_at = now(), used_by = auth.uid() where id = v_inv.id;
  return v_inv.space_id;
end $$;

-- Create an invite and return the raw token once. Only the hash is stored.
create or replace function public.create_invite(p_space uuid, p_role public.member_role, p_phone_hash text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_token text;
begin
  if not public.has_role_at_least(p_space, 'manager') then
    raise exception 'Only an owner or manager can invite people' using errcode = '42501';
  end if;
  if p_role = 'owner' then
    raise exception 'Invites cannot grant the owner role' using errcode = '42501';
  end if;
  v_token := encode(gen_random_bytes(32), 'hex');
  insert into public.invites(space_id, token_hash, role, phone_hash, created_by)
    values (p_space, encode(digest(v_token, 'sha256'), 'hex'), p_role, p_phone_hash, auth.uid());
  return v_token;
end $$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles      enable row level security;
alter table public.spaces        enable row level security;
alter table public.space_members enable row level security;
alter table public.invites       enable row level security;
alter table public.devices       enable row level security;
alter table public.audit_log     enable row level security;

-- profiles: you see your own profile and the profiles of people who share a space with you.
create policy profiles_select on public.profiles for select
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.space_members a
      join public.space_members b on a.space_id = b.space_id
      where a.user_id = auth.uid() and b.user_id = profiles.user_id
    )
  );
create policy profiles_update_own on public.profiles for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- spaces: members read; creation goes through create_space(); owner updates; nobody deletes rows (soft delete via update).
create policy spaces_select on public.spaces for select
  using (public.is_member(id));
create policy spaces_update on public.spaces for update
  using (public.has_role_at_least(id, 'owner'))
  with check (public.has_role_at_least(id, 'owner'));

-- space_members: members see the member list; owner and manager manage it, with limits.
create policy space_members_select on public.space_members for select
  using (public.is_member(space_id));
-- Managers may add members and viewers; owners may add any role. Direct inserts are
-- rare since invites go through accept_invite, but owners adding a known user is allowed.
create policy space_members_insert on public.space_members for insert
  with check (
    (public.has_role_at_least(space_id, 'owner'))
    or (public.has_role_at_least(space_id, 'manager') and role in ('member', 'viewer'))
  );
create policy space_members_update on public.space_members for update
  using (public.has_role_at_least(space_id, 'owner'))
  with check (public.has_role_at_least(space_id, 'owner'));
-- Leave a space yourself, or be removed by an owner (or by a manager if you are member/viewer).
create policy space_members_delete on public.space_members for delete
  using (
    user_id = auth.uid()
    or public.has_role_at_least(space_id, 'owner')
    or (public.has_role_at_least(space_id, 'manager') and role in ('member', 'viewer'))
  );

-- invites: managers and owners see and revoke their space's invites. Creation goes through create_invite().
create policy invites_select on public.invites for select
  using (public.has_role_at_least(space_id, 'manager'));
create policy invites_delete on public.invites for delete
  using (public.has_role_at_least(space_id, 'manager'));

-- devices: your own only.
create policy devices_all_own on public.devices for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- audit_log: owners of a space can read the log rows that belong to that space.
create policy audit_log_select on public.audit_log for select
  using (
    coalesce(new_row->>'space_id', old_row->>'space_id', case when table_name = 'spaces' then row_id end) is not null
    and public.has_role_at_least(
      coalesce(new_row->>'space_id', old_row->>'space_id', case when table_name = 'spaces' then row_id end)::uuid,
      'owner')
  );

-- Grants: the API roles need table access; RLS does the real filtering.
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
revoke all on public.audit_log from authenticated;
grant select on public.audit_log to authenticated;
