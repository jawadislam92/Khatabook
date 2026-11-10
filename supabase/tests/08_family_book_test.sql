-- The private Personal book is gone. New users get a shared Family book,
-- and an old Personal book turns into a Family book that can take members.
begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

do $$
declare
  ali uuid; bilal uuid; home uuid; old uuid; tok text; n int;
begin
  ali := test.new_user('ali@x.com', 'Ali');
  bilal := test.new_user('bilal@x.com', 'Bilal');

  select count(*) into n from public.spaces s join public.space_members m on m.space_id = s.id
    where m.user_id = ali;
  perform test.check(n = 1, 'a new user has exactly one book');
  select s.id into home from public.spaces s join public.space_members m on m.space_id = s.id
    where m.user_id = ali;
  perform test.check((select kind from public.spaces where id = home) = 'group', 'it is shared, not personal');
  perform test.check((select name from public.spaces where id = home) = 'Family', 'it is called Family');
  perform test.check(not (select business_enabled from public.spaces where id = home), 'it is not a business');
  perform test.check((select count(*) from public.books where space_id = home and is_default) = 1,
    'it has its main page for entries');
  perform test.check(not exists (select 1 from public.spaces where kind = 'personal'),
    'nobody gets a personal book any more');

  -- Family can be invited to the starting book and can record in it.
  perform test.login(ali);
  tok := public.create_invite(home, 'member');
  perform test.login(bilal);
  perform public.accept_invite(tok);
  perform test.check((select count(*) from public.space_members where space_id = home) = 2,
    'a family member joins the starting book');

  -- An old personal book (made before this change) is converted the same way.
  reset role;
  insert into public.spaces(name, kind, created_by) values ('Personal', 'personal', ali) returning id into old;
  insert into public.space_members(space_id, user_id, role) values (old, ali, 'owner');
  update public.books set name = 'My Book' where space_id = old;
  update public.books b set name = 'Main' from public.spaces s
    where b.space_id = s.id and s.kind = 'personal' and b.name = 'My Book';
  update public.spaces set kind = 'group', name = case when name = 'Personal' then 'Family' else name end
    where kind = 'personal';
  perform test.check((select kind from public.spaces where id = old) = 'group', 'old personal book is now shared');
  perform test.check((select name from public.spaces where id = old) = 'Family', 'old personal book is renamed Family');
  perform test.check((select name from public.books where space_id = old and is_default) = 'Main',
    'its page is renamed Main');
  perform test.login(ali);
  perform test.check(length(public.create_invite(old, 'member')) = 64, 'old personal book can now take members');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All family book tests passed';
end $$;
rollback;
