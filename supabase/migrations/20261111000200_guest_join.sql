-- Someone who joins from an invite with only a name (a Supabase anonymous
-- sign in) gets a profile but no Family book of their own: they came for
-- the book they were invited to. Everyone else still starts with Family.

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
  if coalesce(new.is_anonymous, false) then
    return new;
  end if;
  insert into public.spaces(name, kind, created_by)
    values ('Family', 'group', new.id) returning id into v_space;
  insert into public.space_members(space_id, user_id, role) values (v_space, new.id, 'owner');
  return new;
end $$;
