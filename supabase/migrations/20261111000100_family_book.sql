-- No more private Personal book. Every new user starts with a shared Family
-- book they can invite people to, and existing Personal books become Family
-- books with the same people and entries.

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
    values ('Family', 'group', new.id) returning id into v_space;
  insert into public.space_members(space_id, user_id, role) values (v_space, new.id, 'owner');
  return new;
end $$;

update public.books b set name = 'Main'
  from public.spaces s
  where b.space_id = s.id and s.kind = 'personal' and b.name = 'My Book';

update public.spaces
  set kind = 'group', name = case when name = 'Personal' then 'Family' else name end
  where kind = 'personal';
