-- Joining from an invite with only a name: a profile with that name, no
-- Family book of their own, and full use of the book they were invited to.
begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

do $$
declare
  ali uuid; nani uuid; fam uuid; tok text; pid uuid; bid uuid; n int;
begin
  ali := test.new_user('ali@x.com', 'Ali');
  select s.id into fam from public.spaces s join public.space_members m on m.space_id = s.id where m.user_id = ali;
  perform test.login(ali);
  tok := public.create_invite(fam, 'member');

  -- Nani joins with only her name (no email).
  reset role;
  insert into auth.users(email, raw_user_meta_data, is_anonymous)
    values (null, jsonb_build_object('display_name', 'Nani Ammi', 'language', 'ur'), true)
    returning id into nani;
  perform test.check((select display_name from public.profiles where user_id = nani) = 'Nani Ammi',
    'the name she typed is her profile name');
  perform test.check((select language from public.profiles where user_id = nani) = 'ur', 'her language is kept');
  select count(*) into n from public.space_members where user_id = nani;
  perform test.check(n = 0, 'no Family book of her own');

  perform test.login(nani);
  perform public.accept_invite(tok);
  perform test.check((select role from public.space_members where space_id = fam and user_id = nani) = 'member',
    'she joins the invited book as a member');

  select id into bid from public.books where space_id = fam and is_default;
  insert into public.parties(space_id, name, created_by) values (fam, 'Doodh wala', nani) returning id into pid;
  insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, created_by)
    values (fam, bid, pid, 'gave', 50000, nani);
  select count(*) into n from public.entries where space_id = fam and created_by = nani;
  perform test.check(n = 1, 'she can write entries in the family book');

  perform test.login(ali);
  select count(*) into n from public.entries where space_id = fam and created_by = nani;
  perform test.check(n = 1, 'the owner sees what she wrote');

  -- A normal sign up still gets a Family book.
  reset role;
  perform test.check((select count(*) from public.space_members where user_id = ali) = 1,
    'email sign ups still start with Family');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All guest join tests passed';
end $$;
rollback;
