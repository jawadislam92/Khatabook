-- Phase 4: invoices. Business profile for the invoice header, numbering per
-- space and year, invoices frozen from job items, payments, void with
-- reversals, and the automatic ledger entries that keep udhaar in step.

-- The audit trigger derives a row id from id, user_id or space_id:user_id.
-- Tables keyed only by space_id (business_profiles) need one more fallback.
create or replace function public.audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_id text;
  v_row jsonb;
begin
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_id := coalesce(v_row->>'id', v_row->>'user_id',
                   case when v_row ? 'space_id' and v_row ? 'user_id' then (v_row->>'space_id') || ':' || (v_row->>'user_id') end,
                   v_row->>'space_id', 'n/a');
  if tg_op = 'DELETE' then
    insert into public.audit_log(table_name, row_id, action, actor_id, old_row)
      values (tg_table_name, v_id, tg_op, auth.uid(), to_jsonb(old));
    return old;
  else
    insert into public.audit_log(table_name, row_id, action, actor_id, old_row, new_row)
      values (tg_table_name, v_id, tg_op, auth.uid(), case when tg_op = 'UPDATE' then to_jsonb(old) end, to_jsonb(new));
    return new;
  end if;
end $$;

create type public.invoice_status as enum ('issued', 'paid', 'void');
create type public.payment_method as enum ('cash', 'bank', 'easypaisa', 'jazzcash', 'other');

-- ---------------------------------------------------------------------------
-- business profile: what prints on the invoice
-- ---------------------------------------------------------------------------
create table public.business_profiles (
  space_id        uuid primary key references public.spaces(id) on delete cascade,
  name_en         text not null default '',
  name_ur         text,
  tagline         text,
  address         text,
  phone           text,
  email           text,
  bank_name       text,
  account_title   text,
  account_number  text,
  easypaisa       text,
  jazzcash        text,
  terms_text      text,
  tax_enabled     boolean not null default false,
  tax_rate_bp     int not null default 0 check (tax_rate_bp between 0 and 10000),
  invoice_prefix  text not null default 'INV' check (char_length(invoice_prefix) between 1 and 8),
  logo_path       text,
  updated_at      timestamptz not null default now()
);
create trigger business_profiles_updated_at before update on public.business_profiles for each row execute function public.set_updated_at();
create trigger audit_business_profiles after insert or update or delete on public.business_profiles for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- numbering
-- ---------------------------------------------------------------------------
create table public.invoice_counters (
  space_id  uuid not null references public.spaces(id) on delete cascade,
  year      int not null,
  next_no   int not null default 1,
  primary key (space_id, year)
);

create or replace function public.next_invoice_number(p_space uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_year int := extract(year from (now() at time zone 'Asia/Karachi'))::int;
  v_no int;
  v_prefix text;
begin
  insert into public.invoice_counters(space_id, year) values (p_space, v_year) on conflict do nothing;
  update public.invoice_counters set next_no = next_no + 1 where space_id = p_space and year = v_year returning next_no - 1 into v_no;
  select coalesce(invoice_prefix, 'INV') into v_prefix from public.business_profiles where space_id = p_space;
  return coalesce(v_prefix, 'INV') || '-' || v_year || '-' || lpad(v_no::text, 4, '0');
end $$;
revoke execute on function public.next_invoice_number(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- invoices, lines, payments
-- ---------------------------------------------------------------------------
create table public.invoices (
  id                uuid primary key default gen_random_uuid(),
  space_id          uuid not null references public.spaces(id) on delete cascade,
  job_id            uuid references public.jobs(id),
  customer_id       uuid not null references public.parties(id),
  number            text not null,
  issued_at         timestamptz not null default now(),
  subtotal_paisa    bigint not null check (subtotal_paisa >= 0),
  discount_paisa    bigint not null default 0 check (discount_paisa >= 0),
  tax_rate_bp       int not null default 0,
  tax_paisa         bigint not null default 0 check (tax_paisa >= 0),
  total_paisa       bigint not null check (total_paisa >= 0),
  received_paisa    bigint not null default 0 check (received_paisa >= 0),
  balance_paisa     bigint not null check (balance_paisa >= 0),
  status            public.invoice_status not null default 'issued',
  notes             text,
  terms_text        text,
  ledger_entry_id   uuid references public.entries(id),
  created_by        uuid not null references auth.users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  voided_at         timestamptz,
  voided_by         uuid references auth.users(id),
  unique (space_id, number)
);
-- One live invoice per job.
create unique index invoices_job_live_idx on public.invoices(job_id) where job_id is not null and status <> 'void';
create index invoices_space_issued_idx on public.invoices(space_id, issued_at desc);
create index invoices_customer_idx on public.invoices(customer_id);
create index invoices_created_by_idx on public.invoices(created_by);
create index invoices_voided_by_idx on public.invoices(voided_by) where voided_by is not null;
create index invoices_ledger_entry_idx on public.invoices(ledger_entry_id);
create trigger invoices_updated_at before update on public.invoices for each row execute function public.set_updated_at();
create trigger audit_invoices after insert or update or delete on public.invoices for each row execute function public.audit_row();

create table public.invoice_lines (
  id                uuid primary key default gen_random_uuid(),
  invoice_id        uuid not null references public.invoices(id) on delete cascade,
  space_id          uuid not null references public.spaces(id) on delete cascade,
  item_id           uuid references public.items(id),
  description       text not null,
  qty               numeric(12,3) not null check (qty > 0),
  unit              text,
  unit_price_paisa  bigint not null check (unit_price_paisa >= 0),
  amount_paisa      bigint not null check (amount_paisa >= 0),
  sort_order        int not null default 0
);
create index invoice_lines_invoice_idx on public.invoice_lines(invoice_id, sort_order);
create index invoice_lines_item_idx on public.invoice_lines(item_id);
create index invoice_lines_space_idx on public.invoice_lines(space_id);

create table public.payments (
  id               uuid primary key default gen_random_uuid(),
  space_id         uuid not null references public.spaces(id) on delete cascade,
  invoice_id       uuid not null references public.invoices(id),
  customer_id      uuid not null references public.parties(id),
  method           public.payment_method not null,
  amount_paisa     bigint not null check (amount_paisa > 0),
  paid_at          timestamptz not null default now(),
  note             text,
  ledger_entry_id  uuid references public.entries(id),
  recorded_by      uuid not null references auth.users(id),
  created_at       timestamptz not null default now(),
  voided_at        timestamptz
);
create index payments_invoice_idx on public.payments(invoice_id);
create index payments_space_paid_idx on public.payments(space_id, paid_at desc);
create index payments_customer_idx on public.payments(customer_id);
create index payments_recorded_by_idx on public.payments(recorded_by);
create index payments_ledger_entry_idx on public.payments(ledger_entry_id);
create trigger audit_payments after insert or update or delete on public.payments for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
create or replace function public.can_bill_job(p_job uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.jobs j where j.id = p_job
      and (public.has_role_at_least(j.space_id, 'manager') or public.is_job_assignee(p_job)))
$$;
revoke execute on function public.can_bill_job(uuid) from public, anon;
grant execute on function public.can_bill_job(uuid) to authenticated;

-- Ledger entry created by the system (invoice or payment), bypassing the
-- "manual only" insert policy because this runs as definer.
create or replace function public.system_entry(
  p_space uuid, p_party uuid, p_direction public.entry_direction, p_amount bigint,
  p_note text, p_source public.entry_source, p_source_id uuid, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_book uuid; v_id uuid;
begin
  select id into v_book from public.books where space_id = p_space and is_default and deleted_at is null;
  insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, entry_date, note, source_type, source_id, created_by)
    values (p_space, v_book, p_party, p_direction, p_amount, (now() at time zone 'Asia/Karachi')::date, p_note, p_source, p_source_id, p_actor)
    returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.system_entry(uuid, uuid, public.entry_direction, bigint, text, public.entry_source, uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- issue an invoice from a job's items
-- ---------------------------------------------------------------------------
create or replace function public.issue_invoice(
  p_job uuid, p_discount_paisa bigint default 0, p_received_paisa bigint default 0,
  p_method public.payment_method default 'cash', p_notes text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  j public.jobs%rowtype;
  bp public.business_profiles%rowtype;
  v_inv uuid; v_sub bigint := 0; v_tax bigint := 0; v_total bigint; v_balance bigint; v_number text; v_entry uuid; v_pay uuid;
  v_cust_name text; v_lines int;
begin
  select * into j from public.jobs where id = p_job for update;
  if not found then raise exception 'Job not found' using errcode = 'P0002'; end if;
  if not public.can_bill_job(p_job) then raise exception 'You are not on this job' using errcode = '42501'; end if;
  if j.status not in ('working', 'finished') then raise exception 'Only a job that is being worked or finished can be invoiced' using errcode = 'check_violation'; end if;
  select count(*) into v_lines from public.job_items where job_id = p_job;
  if v_lines = 0 then raise exception 'Add at least one item or charge first' using errcode = 'check_violation'; end if;
  select * into bp from public.business_profiles where space_id = j.space_id;

  select coalesce(sum(round(qty * unit_price_paisa)), 0)::bigint into v_sub from public.job_items where job_id = p_job;
  if p_discount_paisa < 0 or p_discount_paisa > v_sub then raise exception 'Discount cannot exceed the subtotal' using errcode = 'check_violation'; end if;
  if coalesce(bp.tax_enabled, false) then v_tax := round((v_sub - p_discount_paisa) * bp.tax_rate_bp / 10000.0)::bigint; end if;
  v_total := v_sub - p_discount_paisa + v_tax;
  if p_received_paisa < 0 or p_received_paisa > v_total then raise exception 'Received cannot exceed the total' using errcode = 'check_violation'; end if;
  v_balance := v_total - p_received_paisa;
  v_number := public.next_invoice_number(j.space_id);

  insert into public.invoices(space_id, job_id, customer_id, number, subtotal_paisa, discount_paisa, tax_rate_bp, tax_paisa,
                              total_paisa, received_paisa, balance_paisa, status, notes, terms_text, created_by)
    values (j.space_id, p_job, j.customer_id, v_number, v_sub, p_discount_paisa, case when coalesce(bp.tax_enabled, false) then bp.tax_rate_bp else 0 end, v_tax,
            v_total, p_received_paisa, v_balance, (case when v_balance = 0 then 'paid' else 'issued' end)::public.invoice_status, p_notes, bp.terms_text, auth.uid())
    returning id into v_inv;

  insert into public.invoice_lines(invoice_id, space_id, item_id, description, qty, unit, unit_price_paisa, amount_paisa, sort_order)
    select v_inv, j.space_id, ji.item_id, ji.description, ji.qty, it.unit, ji.unit_price_paisa, round(ji.qty * ji.unit_price_paisa)::bigint,
           row_number() over (order by ji.created_at)
    from public.job_items ji left join public.items it on it.id = ji.item_id where ji.job_id = p_job;

  -- Ledger: the customer owes the total; a payment now is a separate entry so history stays complete.
  select name into v_cust_name from public.parties where id = j.customer_id;
  v_entry := public.system_entry(j.space_id, j.customer_id, 'gave', v_total, 'Invoice ' || v_number || ': ' || j.title, 'invoice', v_inv, auth.uid());
  update public.invoices set ledger_entry_id = v_entry where id = v_inv;
  if p_received_paisa > 0 then
    insert into public.payments(space_id, invoice_id, customer_id, method, amount_paisa, recorded_by)
      values (j.space_id, v_inv, j.customer_id, p_method, p_received_paisa, auth.uid()) returning id into v_pay;
    update public.payments set ledger_entry_id = public.system_entry(j.space_id, j.customer_id, 'got', p_received_paisa,
      'Payment (' || p_method::text || ') for ' || v_number, 'payment', v_pay, auth.uid()) where id = v_pay;
  end if;

  update public.jobs set status = (case when v_balance = 0 then 'paid' else 'invoiced' end)::public.job_status where id = p_job;
  insert into public.job_events(job_id, space_id, event_type, from_status, to_status, actor_id, note)
    values (p_job, j.space_id, 'status', j.status, (case when v_balance = 0 then 'paid' else 'invoiced' end)::public.job_status, auth.uid(), v_number);
  perform public.schedule_job_alerts(p_job);
  perform public.notify_now(j.space_id, 'invoice_issued', p_job, public.space_managers(j.space_id),
    jsonb_build_object('invoice_id', v_inv, 'number', v_number, 'total_paisa', v_total, 'balance_paisa', v_balance,
                       'customer_id', j.customer_id, 'actor_id', auth.uid(), 'space_id', j.space_id, 'title', j.title));
  return v_inv;
end $$;
revoke execute on function public.issue_invoice(uuid, bigint, bigint, public.payment_method, text) from public, anon;
grant execute on function public.issue_invoice(uuid, bigint, bigint, public.payment_method, text) to authenticated;

-- ---------------------------------------------------------------------------
-- record a payment against an invoice
-- ---------------------------------------------------------------------------
create or replace function public.record_payment(
  p_invoice uuid, p_amount_paisa bigint, p_method public.payment_method default 'cash',
  p_paid_at timestamptz default now(), p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare inv public.invoices%rowtype; v_pay uuid; v_number text;
begin
  select * into inv from public.invoices where id = p_invoice for update;
  if not found then raise exception 'Invoice not found' using errcode = 'P0002'; end if;
  if inv.status = 'void' then raise exception 'This invoice is void' using errcode = 'check_violation'; end if;
  if not (public.has_role_at_least(inv.space_id, 'manager') or (inv.job_id is not null and public.is_job_assignee(inv.job_id))) then
    raise exception 'You cannot record payments for this invoice' using errcode = '42501';
  end if;
  if p_amount_paisa <= 0 or p_amount_paisa > inv.balance_paisa then raise exception 'Amount must be between 1 and the balance due' using errcode = 'check_violation'; end if;
  insert into public.payments(space_id, invoice_id, customer_id, method, amount_paisa, paid_at, note, recorded_by)
    values (inv.space_id, p_invoice, inv.customer_id, p_method, p_amount_paisa, p_paid_at, p_note, auth.uid()) returning id into v_pay;
  update public.payments set ledger_entry_id = public.system_entry(inv.space_id, inv.customer_id, 'got', p_amount_paisa,
    'Payment (' || p_method::text || ') for ' || inv.number, 'payment', v_pay, auth.uid()) where id = v_pay;
  update public.invoices set received_paisa = received_paisa + p_amount_paisa, balance_paisa = balance_paisa - p_amount_paisa,
    status = case when balance_paisa - p_amount_paisa = 0 then 'paid'::public.invoice_status else status end where id = p_invoice;
  if inv.balance_paisa - p_amount_paisa = 0 and inv.job_id is not null then
    update public.jobs set status = 'paid' where id = inv.job_id and status = 'invoiced';
    insert into public.job_events(job_id, space_id, event_type, from_status, to_status, actor_id, note)
      values (inv.job_id, inv.space_id, 'status', 'invoiced', 'paid', auth.uid(), inv.number);
  end if;
  perform public.notify_now(inv.space_id, 'payment_received', inv.job_id, public.space_managers(inv.space_id),
    jsonb_build_object('invoice_id', inv.id, 'number', inv.number, 'amount_paisa', p_amount_paisa, 'method', p_method,
                       'customer_id', inv.customer_id, 'actor_id', auth.uid(), 'space_id', inv.space_id));
  return v_pay;
end $$;
revoke execute on function public.record_payment(uuid, bigint, public.payment_method, timestamptz, text) from public, anon;
grant execute on function public.record_payment(uuid, bigint, public.payment_method, timestamptz, text) to authenticated;

-- ---------------------------------------------------------------------------
-- void an invoice: reverse its ledger entries and payments, reopen the job
-- ---------------------------------------------------------------------------
create or replace function public.void_invoice(p_invoice uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare inv public.invoices%rowtype; p record;
begin
  select * into inv from public.invoices where id = p_invoice for update;
  if not found then raise exception 'Invoice not found' using errcode = 'P0002'; end if;
  if inv.status = 'void' then raise exception 'Already void' using errcode = 'check_violation'; end if;
  if not public.has_role_at_least(inv.space_id, 'manager') then raise exception 'Only an owner or manager can void an invoice' using errcode = '42501'; end if;
  for p in select * from public.payments where invoice_id = p_invoice and voided_at is null loop
    if p.ledger_entry_id is not null then perform public.void_entry(p.ledger_entry_id, coalesce(p_note, 'Invoice ' || inv.number || ' voided')); end if;
    update public.payments set voided_at = now() where id = p.id;
  end loop;
  if inv.ledger_entry_id is not null then perform public.void_entry(inv.ledger_entry_id, coalesce(p_note, 'Invoice ' || inv.number || ' voided')); end if;
  update public.invoices set status = 'void', voided_at = now(), voided_by = auth.uid(), balance_paisa = 0 where id = p_invoice;
  if inv.job_id is not null then
    update public.jobs set status = 'finished' where id = inv.job_id and status in ('invoiced', 'paid');
    insert into public.job_events(job_id, space_id, event_type, to_status, actor_id, note)
      values (inv.job_id, inv.space_id, 'status', 'finished', auth.uid(), 'Invoice ' || inv.number || ' voided');
  end if;
end $$;
revoke execute on function public.void_invoice(uuid, text) from public, anon;
grant execute on function public.void_invoice(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- reports
-- ---------------------------------------------------------------------------
create view public.invoice_stats with (security_invoker = true) as
  select s.id as space_id,
         coalesce((select count(*) from public.invoices i where i.space_id = s.id and i.status = 'issued'), 0)::int as unpaid_count,
         coalesce((select sum(balance_paisa) from public.invoices i where i.space_id = s.id and i.status = 'issued'), 0)::bigint as unpaid_paisa,
         coalesce((select sum(total_paisa) from public.invoices i where i.space_id = s.id and i.status <> 'void'
                     and date_trunc('month', i.issued_at at time zone 'Asia/Karachi') = date_trunc('month', now() at time zone 'Asia/Karachi')), 0)::bigint as month_invoiced_paisa,
         coalesce((select sum(amount_paisa) from public.payments p where p.space_id = s.id and p.voided_at is null
                     and date_trunc('month', p.paid_at at time zone 'Asia/Karachi') = date_trunc('month', now() at time zone 'Asia/Karachi')), 0)::bigint as month_received_paisa,
         coalesce((select count(*) from public.jobs j where j.space_id = s.id and j.status in ('finished', 'invoiced', 'paid')
                     and date_trunc('month', j.scheduled_at at time zone 'Asia/Karachi') = date_trunc('month', now() at time zone 'Asia/Karachi')), 0)::int as month_jobs_done
  from public.spaces s where s.business_enabled;

create view public.items_used_month with (security_invoker = true) as
  select l.space_id, l.item_id, min(l.description) as description, min(l.unit) as unit,
         sum(l.qty) as qty, sum(l.amount_paisa)::bigint as amount_paisa
  from public.invoice_lines l join public.invoices i on i.id = l.invoice_id
  where i.status <> 'void' and date_trunc('month', i.issued_at at time zone 'Asia/Karachi') = date_trunc('month', now() at time zone 'Asia/Karachi')
  group by l.space_id, l.item_id;

grant select on public.invoice_stats, public.items_used_month to authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.business_profiles enable row level security;
alter table public.invoice_counters enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_lines enable row level security;
alter table public.payments enable row level security;

create policy business_profiles_select on public.business_profiles for select using (public.is_member(space_id));
create policy business_profiles_insert on public.business_profiles for insert with check (public.has_role_at_least(space_id, 'manager'));
create policy business_profiles_update on public.business_profiles for update
  using (public.has_role_at_least(space_id, 'manager')) with check (public.has_role_at_least(space_id, 'manager'));
grant select, insert, update on public.business_profiles to authenticated;

create policy invoices_select on public.invoices for select using (public.is_member(space_id));
create policy invoice_lines_select on public.invoice_lines for select using (public.is_member(space_id));
create policy payments_select on public.payments for select using (public.is_member(space_id));
grant select on public.invoices, public.invoice_lines, public.payments to authenticated;
-- Counters are internal; nobody reads or writes them through the API.
