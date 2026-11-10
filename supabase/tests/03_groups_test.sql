begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

do $$
declare
  ali uuid; bilal uuid; omar uuid; fam uuid; book uuid; p uuid; tok text; n int; txt text; ok boolean;
  rec record;
begin
  ali := test.new_user('ali@g.com', 'Ali'); bilal := test.new_user('bilal@g.com', 'Bilal'); omar := test.new_user('omar@g.com', 'Omar');
  perform test.login(ali);
  fam := public.create_space('Family');
  select id into book from public.books where space_id = fam;
  insert into public.parties(space_id, name, created_by) values (fam, 'Shop', ali) returning id into p;
  insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, created_by) values (fam, book, p, 'gave', 1000, ali);
  tok := public.create_invite(fam, 'member');

  -- Invite preview works for the invitee, with the right details.
  perform test.login(bilal);
  select * into rec from public.invite_preview(tok);
  perform test.check(rec.space_name = 'Family' and rec.inviter_name = 'Ali' and rec.role = 'member' and rec.valid, 'invite preview shows space, inviter, role');
  select count(*) into n from public.invite_preview('nonsense');
  perform test.check(n = 0, 'preview of an unknown token is empty');
  perform public.accept_invite(tok);
  select * into rec from public.invite_preview(tok);
  perform test.check(rec.valid = false, 'preview of a used invite says not valid');

  -- Activity feed shows the entry and both joins, newest first.
  select count(*) into n from public.activity_feed where space_id = fam;
  perform test.check(n = 3, 'feed has one entry and two member joins');
  -- Inside one transaction every timestamp is identical, so ordering cannot be asserted here.
  select count(*) into n from public.activity_feed where space_id = fam and kind = 'member_joined';
  perform test.check(n = 2, 'feed has a join item per member');
  select actor_name into txt from public.activity_feed where space_id = fam and kind = 'entry_added';
  perform test.check(txt = 'Ali', 'feed names who added the entry');

  -- Member stats.
  select entries_count into n from public.space_member_stats where space_id = fam and user_id = ali;
  perform test.check(n = 1, 'member stats count entries per member');
  select count(*) into n from public.space_member_stats where space_id = fam;
  perform test.check(n = 2, 'member stats list every member');

  -- Stranger sees nothing in the feed or stats.
  perform test.login(omar);
  select count(*) into n from public.activity_feed where space_id = fam;
  perform test.check(n = 0, 'stranger sees no activity');
  select count(*) into n from public.space_member_stats where space_id = fam;
  perform test.check(n = 0, 'stranger sees no member stats');

  -- Leave: member can, last owner cannot, not even from the starting Family book.
  perform test.login(bilal);
  perform public.leave_space(fam);
  select count(*) into n from public.space_members where space_id = fam and user_id = bilal;
  perform test.check(n = 0, 'member can leave');
  perform test.login(ali);
  perform test.check(test.fails(format('select public.leave_space(%L)', fam)), 'last owner cannot leave');
  select s.id into book from public.spaces s where s.name = 'Family' and s.created_by = ali and s.id <> fam;
  perform test.check(book is not null and test.fails(format('select public.leave_space(%L)', book)), 'last owner cannot leave the starting Family book');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All groups tests passed';
end $$;
rollback;
