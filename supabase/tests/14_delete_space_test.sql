begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

do $$
declare
  ali uuid; bilal uuid; omar uuid; shop uuid; other uuid; c uuid; b uuid; j uuid; tok text; open_tok text; n int;
begin
  ali := test.new_user('ali@d.com', 'Ali'); bilal := test.new_user('bilal@d.com', 'Bilal'); omar := test.new_user('omar@d.com', 'Omar');
  perform test.login(ali);
  shop := public.create_space('Shop', true);
  other := public.create_space('Other');
  select id into b from public.books where space_id = shop;
  insert into public.parties(space_id, name, created_by) values (shop, 'Customer', ali) returning id into c;
  insert into public.entries(space_id, book_id, party_id, direction, amount_paisa, created_by) values (shop, b, c, 'gave', 1000, ali);
  tok := public.create_invite(shop, 'manager');
  perform test.login(bilal);
  perform public.accept_invite(tok);
  perform test.login(ali);
  open_tok := public.create_invite(shop, 'member');
  j := public.create_job(shop, c, 'Cameras', 'cctv_install', now() + interval '3 days', array[bilal]);

  perform test.login(omar);
  perform test.check(test.fails(format('select public.delete_space(%L)', shop)), 'a stranger cannot delete');
  perform test.login(bilal);
  perform test.check(test.fails(format('select public.delete_space(%L)', shop)), 'a manager cannot delete');

  perform test.login(ali);
  perform public.delete_space(shop);
  select count(*) into n from public.spaces where id = shop;
  perform test.check(n = 0, 'gone for the owner');
  select count(*) into n from public.spaces where id = other;
  perform test.check(n = 1, 'other groups stay');
  select count(*) into n from public.entries where space_id = shop;
  perform test.check(n = 0, 'entries are hidden');
  perform test.check(test.fails(format('select public.delete_space(%L)', shop)), 'cannot delete twice');
  perform test.check(test.fails(format('insert into public.parties(space_id, name, created_by) values (%L, ''X'', %L)', shop, ali)),
    'nothing can be added');

  perform test.login(bilal);
  select count(*) into n from public.spaces where id = shop;
  perform test.check(n = 0, 'gone for the team');
  select count(*) into n from public.jobs where id = j;
  perform test.check(n = 0, 'jobs are hidden');
  perform test.check(test.fails(format('select public.confirm_job(%L)', j)), 'the assignee cannot act on its job');
  perform test.login(omar);
  perform test.check(test.fails(format('select public.accept_invite(%L)', open_tok)), 'an open invite stops working');

  perform test.logout();
  select count(*) into n from public.scheduled_notifications where space_id = shop and sent_at is null and cancelled_at is null;
  perform test.check(n = 0, 'waiting alerts are cancelled');
  select count(*) into n from public.entries where space_id = shop;
  perform test.check(n = 1, 'the records are kept');
  update public.spaces set deleted_at = null where id = shop;
  perform test.login(bilal);
  select count(*) into n from public.jobs where id = j;
  perform test.check(n = 1, 'a restored group is back for the team');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then raise exception '% test(s) failed', n; end if;
  raise notice 'All delete group tests passed';
end $$;
rollback;
