-- Foundation tests: signup side effects, space isolation, role limits, invites, last owner.
begin;
create schema if not exists test;
create table if not exists test.failures(label text);
\i supabase/tests/helpers.sql
grant usage on schema test to authenticated;
grant all on all tables in schema test to authenticated;
grant execute on all functions in schema test to authenticated;

do $$
declare
  ali uuid; bilal uuid; sara uuid;
  fam uuid; other uuid; tok text; personal_ali uuid;
  n int; r public.member_role;
begin
  -- Signup creates a profile and a shared Family book with the user as owner.
  ali := test.new_user('ali@example.com', 'Ali');
  bilal := test.new_user('bilal@example.com', 'Bilal');
  sara := test.new_user('sara@example.com', 'Sara');

  select count(*) into n from public.profiles where user_id = ali;
  perform test.check(n = 1, 'signup creates profile');
  select s.id into personal_ali from public.spaces s join public.space_members m on m.space_id = s.id
    where m.user_id = ali and s.kind = 'group' and s.name = 'Family' and m.role = 'owner';
  perform test.check(personal_ali is not null, 'signup creates a Family book with owner membership');

  -- Ali creates a family group through the API.
  perform test.login(ali);
  fam := public.create_space('Family');
  select role into r from public.space_members where space_id = fam and user_id = ali;
  perform test.check(r = 'owner', 'creator of a group becomes owner');
  perform test.check((select count(*) from public.spaces where id = fam) = 1, 'creator can read the new space');
  perform test.check(test.fails(format(
    'insert into public.spaces(name, kind, created_by) values (''X'', ''group'', %L)', ali)),
    'direct insert into spaces is refused');
  perform test.check(test.fails(
    'insert into public.spaces(name, kind, created_by) values (''P2'', ''personal'', auth.uid())'),
    'cannot create a second personal space through the API');

  -- Bilal cannot see Ali's spaces.
  perform test.login(bilal);
  select count(*) into n from public.spaces where id in (fam, personal_ali);
  perform test.check(n = 0, 'non member sees no rows of another space');
  select count(*) into n from public.space_members where space_id = fam;
  perform test.check(n = 0, 'non member sees no member list');
  select count(*) into n from public.profiles where user_id = ali;
  perform test.check(n = 0, 'non member cannot read a stranger''s profile');
  perform test.check(test.fails(format(
    'insert into public.space_members(space_id, user_id, role) values (%L, %L, ''owner'')', fam, bilal)),
    'cannot add yourself to a space');

  -- Ali invites Bilal as member; Bilal accepts.
  perform test.login(ali);
  tok := public.create_invite(fam, 'member');
  perform test.check(length(tok) = 64, 'invite returns a 64 char token');
  perform test.check(test.fails(format('select public.create_invite(%L, ''owner'')', fam)),
    'invite cannot grant owner');

  perform test.login(bilal);
  perform test.check(test.fails('select public.accept_invite(''wrongtoken'')'), 'bad token rejected');
  perform public.accept_invite(tok);
  select role into r from public.space_members where space_id = fam and user_id = bilal;
  perform test.check(r = 'member', 'accepted invite grants the invited role');
  perform test.check(test.fails(format('select public.accept_invite(%L)', tok)), 'invite is single use');
  select count(*) into n from public.spaces where id = fam;
  perform test.check(n = 1, 'member can now see the space');
  select count(*) into n from public.profiles where user_id = ali;
  perform test.check(n = 1, 'member can read a co member''s profile');
  select count(*) into n from public.spaces where id = personal_ali;
  perform test.check(n = 0, 'member still cannot see the owner''s own Family book');

  -- Member limits.
  perform test.check(test.fails(format('update public.spaces set name = ''Hacked'' where id = %L', fam)) or
    (select name from public.spaces where id = fam) = 'Family',
    'member cannot rename the space');
  perform test.check(test.fails(format('select public.create_invite(%L, ''member'')', fam)),
    'member cannot create invites');
  perform test.check(test.fails(format(
    'update public.space_members set role = ''owner'' where space_id = %L and user_id = %L', fam, bilal))
    or (select role from public.space_members where space_id = fam and user_id = bilal) = 'member',
    'member cannot promote themselves');
  select count(*) into n from public.invites where space_id = fam;
  perform test.check(n = 0, 'member cannot list invites');

  -- Manager limits.
  perform test.login(ali);
  update public.space_members set role = 'manager' where space_id = fam and user_id = bilal;
  perform test.login(bilal);
  select count(*) into n from public.invites where space_id = fam;
  perform test.check(n = 1, 'manager can list invites');
  tok := public.create_invite(fam, 'viewer');
  perform test.login(sara);
  perform public.accept_invite(tok);
  perform test.login(bilal);
  perform test.check(test.fails(format(
    'update public.space_members set role = ''owner'' where space_id = %L and user_id = %L', fam, sara))
    or (select role from public.space_members where space_id = fam and user_id = sara) = 'viewer',
    'manager cannot change roles');
  delete from public.space_members where space_id = fam and user_id = sara;
  select count(*) into n from public.space_members where space_id = fam and user_id = sara;
  perform test.check(n = 0, 'manager can remove a viewer');
  delete from public.space_members where space_id = fam and user_id = ali;
  select count(*) into n from public.space_members where space_id = fam and user_id = ali;
  perform test.check(n = 1, 'manager cannot remove the owner');

  -- Last owner protection.
  perform test.login(ali);
  perform test.check(test.fails(format(
    'delete from public.space_members where space_id = %L and user_id = %L', fam, ali)),
    'the last owner cannot leave');
  perform test.check(test.fails(format(
    'update public.space_members set role = ''member'' where space_id = %L and user_id = %L', fam, ali)),
    'the last owner cannot demote themselves');

  -- Devices are private.
  perform test.login(ali);
  insert into public.devices(user_id, fcm_token, platform) values (ali, 'tok-ali', 'android');
  perform test.login(bilal);
  select count(*) into n from public.devices;
  perform test.check(n = 0, 'devices of other users are invisible');
  perform test.check(test.fails(format(
    'insert into public.devices(user_id, fcm_token, platform) values (%L, ''tok-x'', ''android'')', ali)),
    'cannot register a device for another user');

  -- Audit log recorded membership changes and is readable by the owner only.
  perform test.login(ali);
  select count(*) into n from public.audit_log where table_name = 'space_members' and new_row->>'space_id' = fam::text;
  perform test.check(n >= 3, 'audit log records membership changes');
  perform test.login(bilal);
  select count(*) into n from public.audit_log where new_row->>'space_id' = fam::text;
  perform test.check(n = 0, 'manager cannot read the audit log');

  -- Expired invite.
  perform test.login(ali);
  tok := public.create_invite(fam, 'member');
  perform test.logout();
  update public.invites set expires_at = now() - interval '1 minute' where token_hash = encode(extensions.digest(tok, 'sha256'), 'hex');
  perform test.login(sara);
  perform test.check(test.fails(format('select public.accept_invite(%L)', tok)), 'expired invite rejected');
end $$;

do $$
declare n int;
begin
  select count(*) into n from test.failures;
  if n > 0 then
    raise exception '% test(s) failed', n;
  end if;
  raise notice 'All foundation tests passed';
end $$;
rollback;
