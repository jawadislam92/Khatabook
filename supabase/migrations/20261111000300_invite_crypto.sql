-- Invites never worked on the real servers. Supabase keeps pgcrypto
-- (gen_random_bytes, digest) in the "extensions" schema, but these three
-- functions only look in "public", so creating, previewing and accepting an
-- invite all failed with "function gen_random_bytes does not exist".
-- The local test database now keeps pgcrypto in "extensions" too.
alter function public.create_invite(uuid, public.member_role, text) set search_path = public, extensions;
alter function public.accept_invite(text) set search_path = public, extensions;
alter function public.invite_preview(text) set search_path = public, extensions;
