begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

do $$
declare
  uncle uuid; saeed uuid; munshi uuid; omar uuid;
  biz uuid; cust uuid; job uuid; job2 uuid; cam uuid; cable uuid; svc uuid; tok text; inv uuid; inv2 uuid; pay uuid;
  n int; bal bigint; txt text; st text; jst public.job_status; r record;
begin
  uncle := test.new_user('u@i.com', 'Ahmed'); saeed := test.new_user('s@i.com', 'Saeed'); munshi := test.new_user('m@i.com', 'Munshi'); omar := test.new_user('o@i.com', 'Omar');
  perform test.login(uncle);
  biz := public.create_space('Ahmed CCTV', true);
  tok := public.create_invite(biz, 'member'); perform test.login(saeed); perform public.accept_invite(tok);
  perform test.login(uncle);
  tok := public.create_invite(biz, 'viewer'); perform test.login(munshi); perform public.accept_invite(tok);
  perform test.login(uncle);
  insert into public.business_profiles(space_id, name_en, invoice_prefix, terms_text) values (biz, 'Ahmed CCTV & Solar', 'INV', '6 months warranty');
  insert into public.parties(space_id, name, is_customer, created_by) values (biz, 'Mr Ahmed F-10', true, uncle) returning id into cust;
  insert into public.items(space_id, name_en, unit, sale_price_paisa, created_by) values (biz, 'Dome camera 2MP', 'pc', 450000, uncle) returning id into cam;
  insert into public.items(space_id, name_en, unit, sale_price_paisa, created_by) values (biz, 'Coaxial cable', 'm', 4500, uncle) returning id into cable;
  insert into public.items(space_id, name_en, unit, sale_price_paisa, allow_price_edit, created_by) values (biz, 'Service charge', 'visit', 150000, true, uncle) returning id into svc;
  job := public.create_job(biz, cust, '2 cameras not recording', 'cctv_repair', now() + interval '1 hour', array[saeed]);

  -- Installer finishes the job and records what was used.
  perform test.login(saeed);
  perform public.set_job_status(job, 'working');
  insert into public.job_items(job_id, space_id, item_id, description, qty, unit_price_paisa, created_by) values
    (job, biz, cam, 'Dome camera 2MP', 2, 450000, saeed),
    (job, biz, cable, 'Coaxial cable', 20, 4500, saeed),
    (job, biz, svc, 'Service charge', 1, 150000, saeed);
  perform public.set_job_status(job, 'finished');

  -- Viewer cannot issue; stranger cannot issue.
  perform test.login(munshi);
  perform test.check(test.fails(format('select public.issue_invoice(%L)', job)), 'viewer cannot issue an invoice');
  perform test.login(omar);
  perform test.check(test.fails(format('select public.issue_invoice(%L)', job)), 'stranger cannot issue an invoice');

  -- Installer issues with a discount and cash received now.
  perform test.login(saeed);
  inv := public.issue_invoice(job, 50000, 500000, 'cash', 'Thank you');
  select number, total_paisa, balance_paisa, status::text into txt, bal, n, st from public.invoices where id = inv;
  select number into txt from public.invoices where id = inv;
  perform test.check(txt = 'INV-' || extract(year from now())::int || '-0001', 'first invoice is numbered 0001 with the prefix');
  select total_paisa into bal from public.invoices where id = inv;
  perform test.check(bal = 900000 + 90000 + 150000 - 50000, 'total is subtotal minus discount, no tax');
  select balance_paisa into bal from public.invoices where id = inv;
  perform test.check(bal = 1090000 - 500000, 'balance is total minus received');
  select count(*) into n from public.invoice_lines where invoice_id = inv;
  perform test.check(n = 3, 'lines are frozen from job items');
  select status into jst from public.jobs where id = job;
  perform test.check(jst = 'invoiced', 'job moves to invoiced');
  select count(*) into n from public.payments where invoice_id = inv and voided_at is null;
  perform test.check(n = 1, 'cash received now is a payment row');
  -- Ledger: customer owes exactly the balance.
  select balance_paisa into bal from public.party_balances where party_id = cust;
  perform test.check(bal = 590000, 'customer ledger balance equals the invoice balance due');
  select count(*) into n from public.entries where party_id = cust and source_type = 'invoice';
  perform test.check(n = 1, 'invoice entry is in the ledger');
  perform test.check(test.fails(format('select public.issue_invoice(%L)', job)), 'a job cannot be invoiced twice');
  perform test.check(test.fails(format('delete from public.job_items where job_id = %L', job)), 'items are frozen once invoiced');
  -- The installer's ledger entry from the invoice cannot have its amount changed.
  perform test.login(uncle);
  select ledger_entry_id into inv2 from public.invoices where id = inv;
  perform test.check(test.fails(format('update public.entries set amount_paisa = 1 where id = %L', inv2)), 'invoice ledger entry amount is locked');

  -- Partial payment, then the rest. Installer may record; viewer may not.
  perform test.login(munshi);
  perform test.check(test.fails(format('select public.record_payment(%L, 100000)', inv)), 'viewer cannot record a payment');
  perform test.login(saeed);
  perform test.check(test.fails(format('select public.record_payment(%L, 999999999)', inv)), 'payment cannot exceed the balance');
  pay := public.record_payment(inv, 90000, 'easypaisa');
  select balance_paisa into bal from public.invoices where id = inv;
  perform test.check(bal = 500000, 'partial payment reduces the balance');
  select balance_paisa into bal from public.party_balances where party_id = cust;
  perform test.check(bal = 500000, 'ledger follows the partial payment');
  pay := public.record_payment(inv, 500000, 'bank');
  select status::text into st from public.invoices where id = inv;
  perform test.check(st = 'paid', 'full payment marks the invoice paid');
  select status into jst from public.jobs where id = job;
  perform test.check(jst = 'paid', 'job moves to paid');
  select balance_paisa into bal from public.party_balances where party_id = cust;
  perform test.check(bal = 0, 'customer owes nothing after full payment');
  perform test.check(test.fails(format('select public.record_payment(%L, 1)', inv)), 'cannot pay a paid invoice');

  -- Stats view.
  perform test.login(uncle);
  select month_invoiced_paisa, month_received_paisa, unpaid_count into r from public.invoice_stats where space_id = biz;
  perform test.check(r.month_invoiced_paisa = 1090000 and r.month_received_paisa = 1090000 and r.unpaid_count = 0, 'stats reflect the month');
  select count(*) into n from public.items_used_month where space_id = biz;
  perform test.check(n = 3, 'items used this month lists each item');

  -- Void: installer cannot; manager can; ledger returns to zero and job reopens.
  perform test.login(saeed);
  perform test.check(test.fails(format('select public.void_invoice(%L)', inv)), 'installer cannot void an invoice');
  perform test.login(uncle);
  perform public.void_invoice(inv, 'wrong customer');
  select status::text into st from public.invoices where id = inv;
  perform test.check(st = 'void', 'invoice is void');
  select balance_paisa into bal from public.party_balances where party_id = cust;
  perform test.check(bal = 0, 'ledger is back to zero after void (reversals cancel)');
  select count(*) into n from public.entries where party_id = cust and source_type = 'reversal';
  perform test.check(n = 4, 'four reversals: the invoice and three payments');
  select status into jst from public.jobs where id = job;
  perform test.check(jst = 'finished', 'job reopens as finished after void');
  -- Can issue again after void, with the next number.
  perform test.login(saeed);
  inv2 := public.issue_invoice(job, 0, 0);
  select number into txt from public.invoices where id = inv2;
  perform test.check(txt like '%-0002', 'second invoice takes the next number');
  select balance_paisa into bal from public.party_balances where party_id = cust;
  perform test.check(bal = 1140000, 'reissued invoice puts the full amount back on the ledger');

  -- Tax enabled on the profile applies to the next invoice.
  perform test.login(uncle);
  update public.business_profiles set tax_enabled = true, tax_rate_bp = 1800 where space_id = biz;
  job2 := public.create_job(biz, cust, 'Solar check', 'solar_service', now() + interval '2 hours', array[saeed]);
  perform test.login(saeed);
  perform public.set_job_status(job2, 'working');
  insert into public.job_items(job_id, space_id, item_id, description, qty, unit_price_paisa, created_by) values (job2, biz, svc, 'Service charge', 1, 100000, saeed);
  inv := public.issue_invoice(job2);
  select tax_paisa, total_paisa into r from public.invoices where id = inv;
  perform test.check(r.tax_paisa = 18000 and r.total_paisa = 118000, '18 percent tax applied when enabled');

  -- Stranger sees nothing.
  perform test.login(omar);
  select count(*) into n from public.invoices where space_id = biz;
  perform test.check(n = 0, 'stranger sees no invoices');
  select count(*) into n from public.business_profiles where space_id = biz;
  perform test.check(n = 0, 'stranger sees no business profile');
  perform test.check(test.fails(format('insert into public.business_profiles(space_id, name_en) values (%L, ''x'')', biz)), 'stranger cannot write a business profile');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All invoice tests passed';
end $$;
rollback;
