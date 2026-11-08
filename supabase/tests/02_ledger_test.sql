-- Ledger tests: default books, entries, balances, void and reversal, month lock, roles.
begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

do $$
declare
  ali uuid; bilal uuid; sara uuid; omar uuid;
  fam uuid; book uuid; other_space uuid; other_book uuid; other_party uuid;
  p_bilal uuid; p_shop uuid;
  e1 uuid; e2 uuid; e3 uuid; rev uuid; tok text;
  n int; bal bigint; get_p bigint; give_p bigint;
begin
  ali := test.new_user('ali@x.com', 'Ali');
  bilal := test.new_user('bilal@x.com', 'Bilal');
  sara := test.new_user('sara@x.com', 'Sara');
  omar := test.new_user('omar@x.com', 'Omar');

  -- Default books exist for the personal spaces and for a new group.
  perform test.login(ali);
  select count(*) into n from public.books where is_default;
  perform test.check(n = 1, 'personal space has a default book');
  fam := public.create_space('Family');
  select id into book from public.books where space_id = fam and is_default;
  perform test.check(book is not null, 'new group gets a default book');

  -- Members: bilal as member, sara as viewer.
  tok := public.create_invite(fam, 'member'); perform test.login(bilal); perform public.accept_invite(tok);
  perform test.login(ali);
  tok := public.create_invite(fam, 'viewer'); perform test.login(sara); perform public.accept_invite(tok);

  -- Ali adds parties and entries.
  perform test.login(ali);
  insert into public.parties(space_id, name, created_by) values (fam, 'Bilal Bhai', ali) returning id into p_bilal;
  insert into public.parties(space_id, name, created_by) values (fam, 'Corner Shop', ali) returning id into p_shop;
  insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, created_by)
    values (fam, book, p_bilal, 'gave', 500000, ali) returning id into e1;
  insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, created_by)
    values (fam, book, p_bilal, 'got', 200000, ali) returning id into e2;
  insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, created_by)
    values (fam, book, p_shop, 'got', 150000, ali) returning id into e3;

  select balance_paisa into bal from public.party_balances where party_id = p_bilal;
  perform test.check(bal = 300000, 'balance: gave 5000, got 2000, they owe 3000');
  select balance_paisa into bal from public.party_balances where party_id = p_shop;
  perform test.check(bal = -150000, 'balance: got 1500 from shop means we owe 1500');
  select will_get_paisa, will_give_paisa into get_p, give_p from public.space_totals where space_id = fam;
  perform test.check(get_p = 300000 and give_p = 150000, 'space totals split will get and will give');

  -- Viewer can read but not write.
  perform test.login(sara);
  select count(*) into n from public.entries where space_id = fam;
  perform test.check(n = 3, 'viewer sees entries');
  perform test.check(test.fails(format(
    'insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, created_by) values (%L,%L,%L,''gave'',100,%L)',
    fam, book, p_bilal, sara)), 'viewer cannot add an entry');
  perform test.check(test.fails(format(
    'insert into public.parties(space_id, name, created_by) values (%L, ''X'', %L)', fam, sara)), 'viewer cannot add a party');

  -- Member adds an entry, can edit own note, cannot edit someone else's amount.
  perform test.login(bilal);
  insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, note, created_by)
    values (fam, book, p_shop, 'gave', 50000, 'paid bill', bilal) returning id into rev;
  update public.entries set note = 'paid electricity bill' where id = rev;
  select note into tok from public.entries where id = rev;
  perform test.check(tok = 'paid electricity bill', 'member edits own entry note');
  update public.entries set amount_paisa = 1 where id = e1;
  select amount_paisa into bal from public.entries where id = e1;
  perform test.check(bal = 500000, 'member cannot edit another member''s entry');
  perform test.check(test.fails(format('delete from public.entries where id = %L', rev)), 'entries cannot be deleted');
  perform test.check(test.fails(format(
    'insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, created_by) values (%L,%L,%L,''gave'',100,%L)',
    fam, book, p_bilal, ali)), 'cannot add an entry in someone else''s name');
  perform test.check(test.fails(format(
    'insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, source_type, created_by) values (%L,%L,%L,''gave'',100,''invoice'',%L)',
    fam, book, p_bilal, bilal)), 'cannot fake an invoice entry');

  -- Void creates a reversal and restores the balance; voiding twice fails.
  perform test.login(ali);
  rev := public.void_entry(e2, 'entered by mistake');
  select balance_paisa into bal from public.party_balances where party_id = p_bilal;
  perform test.check(bal = 500000, 'voiding the 2000 receipt puts the balance back to 5000');
  select count(*) into n from public.entries where reversal_of = e2 and source_type = 'reversal';
  perform test.check(n = 1, 'void inserts a reversal row');
  select count(*) into n from public.entries where id = e2 and voided_at is not null;
  perform test.check(n = 1, 'original is marked voided, not removed');
  perform test.check(test.fails(format('select public.void_entry(%L)', e2)), 'cannot void twice');
  perform test.check(test.fails(format('update public.entries set note = ''x'' where id = %L', e2)) or
    (select note from public.entries where id = e2) is null, 'voided entry cannot change');
  perform test.login(bilal);
  perform test.check(test.fails(format('select public.void_entry(%L)', e1)), 'member cannot void another member''s entry');

  -- Audit log keeps the old note after an edit.
  perform test.login(ali);
  select count(*) into n from public.audit_log where table_name = 'entries' and action = 'UPDATE' and old_row->>'note' = 'paid bill';
  perform test.check(n = 1, 'audit log keeps the previous version of an edited entry');

  -- Month lock: only the owner sets it; after that nothing dated inside changes.
  perform test.login(bilal);
  update public.books set locked_until = current_date where id = book;
  select locked_until into tok from public.books where id = book;
  perform test.check(tok is null, 'member cannot lock a month');
  perform test.login(ali);
  update public.books set locked_until = current_date - 1 where id = book;
  perform test.check(test.fails(format(
    'insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, entry_date, created_by) values (%L,%L,%L,''gave'',100,current_date - 5,%L)',
    fam, book, p_bilal, ali)), 'cannot add an entry inside a locked month');
  insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, entry_date, created_by)
    values (fam, book, p_bilal, 'gave', 100, current_date, ali);
  perform test.check(true, 'can still add an entry after the lock date');
  update public.books set locked_until = null where id = book;

  -- Cross space isolation and cross reference blocking.
  perform test.login(omar);
  other_space := public.create_space('Other');
  select id into other_book from public.books where space_id = other_space;
  insert into public.parties(space_id, name, created_by) values (other_space, 'Someone', omar) returning id into other_party;
  select count(*) into n from public.entries where space_id = fam;
  perform test.check(n = 0, 'stranger sees no entries of the family');
  select count(*) into n from public.party_balances where space_id = fam;
  perform test.check(n = 0, 'stranger sees no balances of the family');
  perform test.check(test.fails(format(
    'insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, created_by) values (%L,%L,%L,''gave'',100,%L)',
    other_space, other_book, p_bilal, omar)), 'cannot attach an entry to a party from another space');
  perform test.check(test.fails(format(
    'insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, created_by) values (%L,%L,%L,''gave'',100,%L)',
    other_space, book, other_party, omar)), 'cannot write into a book from another space');

  -- Reminders.
  perform test.login(bilal);
  insert into public.reminders(space_id, party_id, due_date, created_by) values (fam, p_bilal, current_date + 7, bilal);
  perform test.login(sara);
  select count(*) into n from public.reminders where space_id = fam;
  perform test.check(n = 1, 'viewer sees reminders');
  perform test.check(test.fails(format('insert into public.reminders(space_id, party_id, due_date, created_by) values (%L,%L,current_date,%L)', fam, p_bilal, sara)),
    'viewer cannot add a reminder');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All ledger tests passed';
end $$;
rollback;
