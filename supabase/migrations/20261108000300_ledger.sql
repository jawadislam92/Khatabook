-- Phase 1: the ledger. Books, parties, entries, attachments, reminders, balances.
--
-- Money convention: an entry with direction 'gave' means we handed money or goods
-- to the party, so the party owes us. 'got' means they paid us. A party balance is
-- sum(gave) - sum(got): positive means "you will get", negative "you will give".
--
-- Entries are append only. Editing a field is allowed within rules and leaves the
-- old row in audit_log. Deleting is replaced by void_entry(), which inserts a
-- reversal and marks the original, so history never disappears.

create type public.entry_direction as enum ('gave', 'got');
create type public.entry_source as enum ('manual', 'invoice', 'payment', 'reversal');

-- ---------------------------------------------------------------------------
-- books
-- ---------------------------------------------------------------------------
create table public.books (
  id            uuid primary key default gen_random_uuid(),
  space_id      uuid not null references public.spaces(id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 80),
  locked_until  date,                        -- entries dated on or before this day cannot change
  is_default    boolean not null default false,
  created_by    uuid not null references auth.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index books_space_idx on public.books(space_id);
create unique index books_one_default_idx on public.books(space_id) where is_default and deleted_at is null;
create trigger books_updated_at before update on public.books
  for each row execute function public.set_updated_at();
create trigger audit_books after insert or update or delete on public.books
  for each row execute function public.audit_row();

-- Every space gets a default book the moment it exists.
create or replace function public.handle_new_space_book()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.books(space_id, name, is_default, created_by)
    values (new.id, case when new.kind = 'personal' then 'My Book' else 'Main' end, true, new.created_by);
  return new;
end $$;
revoke execute on function public.handle_new_space_book() from public, anon, authenticated;
create trigger on_space_created_book after insert on public.spaces
  for each row execute function public.handle_new_space_book();

-- Backfill for spaces that already exist.
insert into public.books(space_id, name, is_default, created_by)
  select s.id, case when s.kind = 'personal' then 'My Book' else 'Main' end, true, s.created_by
  from public.spaces s
  where not exists (select 1 from public.books b where b.space_id = s.id and b.is_default);

-- ---------------------------------------------------------------------------
-- parties
-- ---------------------------------------------------------------------------
create table public.parties (
  id              uuid primary key default gen_random_uuid(),
  space_id        uuid not null references public.spaces(id) on delete cascade,
  name            text not null check (char_length(name) between 1 and 120),
  phone_hash      text,
  phone_display   text,
  photo_path      text,
  linked_user_id  uuid references auth.users(id),
  is_customer     boolean not null default false,
  address         text,
  geo_lat         double precision,
  geo_lng         double precision,
  notes           text,
  created_by      uuid not null references auth.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index parties_space_idx on public.parties(space_id) where deleted_at is null;
create index parties_name_idx on public.parties(space_id, lower(name));
create index parties_linked_user_idx on public.parties(linked_user_id) where linked_user_id is not null;
create index parties_created_by_idx on public.parties(created_by);
create trigger parties_updated_at before update on public.parties
  for each row execute function public.set_updated_at();
create trigger audit_parties after insert or update or delete on public.parties
  for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- entries
-- ---------------------------------------------------------------------------
create table public.entries (
  id            uuid primary key default gen_random_uuid(),
  space_id      uuid not null references public.spaces(id) on delete cascade,
  book_id       uuid not null references public.books(id),
  party_id      uuid not null references public.parties(id),
  direction     public.entry_direction not null,
  amount_paisa  bigint not null check (amount_paisa > 0),
  entry_date    date not null default current_date,
  note          text check (note is null or char_length(note) <= 500),
  source_type   public.entry_source not null default 'manual',
  source_id     uuid,
  reversal_of   uuid references public.entries(id),
  voided_at     timestamptz,
  voided_by     uuid references auth.users(id),
  created_by    uuid not null references auth.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index entries_party_idx on public.entries(party_id, entry_date desc);
create index entries_book_idx on public.entries(book_id, entry_date desc);
create index entries_space_date_idx on public.entries(space_id, entry_date desc);
create index entries_reversal_idx on public.entries(reversal_of) where reversal_of is not null;
create index entries_created_by_idx on public.entries(created_by);
create index entries_voided_by_idx on public.entries(voided_by) where voided_by is not null;
create trigger entries_updated_at before update on public.entries
  for each row execute function public.set_updated_at();
create trigger audit_entries after insert or update or delete on public.entries
  for each row execute function public.audit_row();

-- Consistency: the party and book must belong to the entry's space, and a month
-- lock on the book freezes everything dated inside it.
create or replace function public.check_entry()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_lock date;
  v_book_space uuid;
  v_party_space uuid;
begin
  select locked_until, space_id into v_lock, v_book_space from public.books where id = new.book_id and deleted_at is null;
  if v_book_space is null or v_book_space <> new.space_id then
    raise exception 'Book does not belong to this space' using errcode = 'check_violation';
  end if;
  select space_id into v_party_space from public.parties where id = new.party_id and deleted_at is null;
  if v_party_space is null or v_party_space <> new.space_id then
    raise exception 'Party does not belong to this space' using errcode = 'check_violation';
  end if;
  if v_lock is not null and new.entry_date <= v_lock then
    raise exception 'This month is locked' using errcode = 'check_violation';
  end if;
  if tg_op = 'UPDATE' then
    if v_lock is not null and old.entry_date <= v_lock then
      raise exception 'This month is locked' using errcode = 'check_violation';
    end if;
    -- Only these fields may change, and only on live manual entries.
    if old.voided_at is not null then
      raise exception 'A voided entry cannot change' using errcode = 'check_violation';
    end if;
    if old.source_type <> 'manual' and (new.amount_paisa <> old.amount_paisa or new.direction <> old.direction) then
      raise exception 'Entries created from invoices or payments change through their source' using errcode = 'check_violation';
    end if;
    if new.space_id <> old.space_id or new.book_id <> old.book_id or new.created_by <> old.created_by
       or new.source_type <> old.source_type or new.reversal_of is distinct from old.reversal_of then
      raise exception 'That field cannot change' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.check_entry() from public, anon, authenticated;
create trigger entries_check before insert or update on public.entries
  for each row execute function public.check_entry();

-- No deletes, ever. Voiding is the only way.
create or replace function public.block_delete()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'Entries are never deleted. Use void_entry.' using errcode = '42501';
end $$;
revoke execute on function public.block_delete() from public, anon, authenticated;
create trigger entries_no_delete before delete on public.entries
  for each row execute function public.block_delete();

-- Void an entry: inserts the opposite entry and marks the original.
create or replace function public.void_entry(p_entry uuid, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v public.entries%rowtype;
  v_rev uuid;
begin
  select * into v from public.entries where id = p_entry for update;
  if not found then
    raise exception 'Entry not found' using errcode = 'P0002';
  end if;
  if v.voided_at is not null then
    raise exception 'Already voided' using errcode = 'check_violation';
  end if;
  if not (public.has_role_at_least(v.space_id, 'manager')
          or (v.created_by = auth.uid() and public.has_role_at_least(v.space_id, 'member'))) then
    raise exception 'You cannot void this entry' using errcode = '42501';
  end if;
  insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, entry_date, note,
                             source_type, reversal_of, created_by)
    values (v.space_id, v.book_id, v.party_id,
            case when v.direction = 'gave' then 'got' else 'gave' end::public.entry_direction,
            v.amount_paisa, current_date, coalesce(p_note, 'Reversal'), 'reversal', v.id, auth.uid())
    returning id into v_rev;
  update public.entries set voided_at = now(), voided_by = auth.uid() where id = v.id;
  return v_rev;
end $$;
revoke execute on function public.void_entry(uuid, text) from public, anon;
grant execute on function public.void_entry(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- attachments and reminders
-- ---------------------------------------------------------------------------
create table public.entry_attachments (
  id            uuid primary key default gen_random_uuid(),
  entry_id      uuid not null references public.entries(id) on delete cascade,
  space_id      uuid not null references public.spaces(id) on delete cascade,
  storage_path  text not null,
  mime          text not null,
  size_bytes    int not null check (size_bytes between 1 and 5242880),
  created_by    uuid not null references auth.users(id),
  created_at    timestamptz not null default now()
);
create index entry_attachments_entry_idx on public.entry_attachments(entry_id);
create index entry_attachments_created_by_idx on public.entry_attachments(created_by);

create table public.reminders (
  id          uuid primary key default gen_random_uuid(),
  space_id    uuid not null references public.spaces(id) on delete cascade,
  party_id    uuid not null references public.parties(id) on delete cascade,
  due_date    date not null,
  note        text,
  done_at     timestamptz,
  created_by  uuid not null references auth.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index reminders_space_due_idx on public.reminders(space_id, due_date) where done_at is null;
create index reminders_party_idx on public.reminders(party_id);
create index reminders_created_by_idx on public.reminders(created_by);
create trigger reminders_updated_at before update on public.reminders
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- balances (views run as the caller, so RLS on entries still applies)
-- ---------------------------------------------------------------------------
create view public.party_balances with (security_invoker = true) as
  select p.id as party_id, p.space_id,
         coalesce(sum(case when e.direction = 'gave' then e.amount_paisa else -e.amount_paisa end), 0)::bigint as balance_paisa,
         count(e.id) filter (where e.voided_at is null and e.source_type <> 'reversal')::int as entry_count,
         max(e.entry_date) as last_entry_date
  from public.parties p
  -- Voided originals stay in the sum: their reversal cancels them exactly.
  left join public.entries e on e.party_id = p.id
  where p.deleted_at is null
  group by p.id, p.space_id;

create view public.space_totals with (security_invoker = true) as
  select space_id,
         coalesce(sum(balance_paisa) filter (where balance_paisa > 0), 0)::bigint as will_get_paisa,
         coalesce(-sum(balance_paisa) filter (where balance_paisa < 0), 0)::bigint as will_give_paisa
  from public.party_balances
  group by space_id;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.books             enable row level security;
alter table public.parties           enable row level security;
alter table public.entries           enable row level security;
alter table public.entry_attachments enable row level security;
alter table public.reminders         enable row level security;

-- books
create policy books_select on public.books for select using (public.is_member(space_id));
create policy books_insert on public.books for insert
  with check (public.has_role_at_least(space_id, 'manager') and created_by = (select auth.uid()));
-- Renaming is for managers; locking is for owners (checked in the trigger below).
create policy books_update on public.books for update
  using (public.has_role_at_least(space_id, 'manager'))
  with check (public.has_role_at_least(space_id, 'manager'));

create or replace function public.check_book_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.locked_until is distinct from old.locked_until and not public.has_role_at_least(old.space_id, 'owner') then
    raise exception 'Only the owner can lock or unlock a month' using errcode = '42501';
  end if;
  if new.space_id <> old.space_id or new.is_default <> old.is_default then
    raise exception 'That field cannot change' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke execute on function public.check_book_update() from public, anon, authenticated;
create trigger books_check before update on public.books
  for each row execute function public.check_book_update();

-- parties
create policy parties_select on public.parties for select using (public.is_member(space_id));
create policy parties_insert on public.parties for insert
  with check (public.has_role_at_least(space_id, 'member') and created_by = (select auth.uid()));
create policy parties_update on public.parties for update
  using (public.has_role_at_least(space_id, 'member'))
  with check (public.has_role_at_least(space_id, 'member'));

-- entries: members add; the creator or a manager edits; nobody deletes.
create policy entries_select on public.entries for select using (public.is_member(space_id));
create policy entries_insert on public.entries for insert
  with check (
    public.has_role_at_least(space_id, 'member')
    and created_by = (select auth.uid())
    and source_type = 'manual'
    and reversal_of is null
    and voided_at is null
  );
create policy entries_update on public.entries for update
  using (
    public.has_role_at_least(space_id, 'manager')
    or (created_by = (select auth.uid()) and public.has_role_at_least(space_id, 'member'))
  )
  with check (
    public.has_role_at_least(space_id, 'manager')
    or (created_by = (select auth.uid()) and public.has_role_at_least(space_id, 'member'))
  );

-- attachments
create policy entry_attachments_select on public.entry_attachments for select using (public.is_member(space_id));
create policy entry_attachments_insert on public.entry_attachments for insert
  with check (public.has_role_at_least(space_id, 'member') and created_by = (select auth.uid()));
create policy entry_attachments_delete on public.entry_attachments for delete
  using (public.has_role_at_least(space_id, 'manager') or created_by = (select auth.uid()));

-- reminders
create policy reminders_select on public.reminders for select using (public.is_member(space_id));
create policy reminders_insert on public.reminders for insert
  with check (public.has_role_at_least(space_id, 'member') and created_by = (select auth.uid()));
create policy reminders_update on public.reminders for update
  using (public.has_role_at_least(space_id, 'member'))
  with check (public.has_role_at_least(space_id, 'member'));
create policy reminders_delete on public.reminders for delete
  using (public.has_role_at_least(space_id, 'manager') or created_by = (select auth.uid()));

-- Grants
grant select, insert, update on public.books, public.parties, public.entries to authenticated;
grant select, insert, delete on public.entry_attachments to authenticated;
grant select, insert, update, delete on public.reminders to authenticated;
grant select on public.party_balances, public.space_totals to authenticated;
revoke delete on public.books, public.parties, public.entries from authenticated;
