-- Names of the tables the nightly backup exports. Only the service role can
-- call this (no grant to authenticated), and views are left out because they
-- are derived from the tables.
create or replace function public.backup_table_names()
returns table (table_name text) language sql stable security definer set search_path = public as $$
  select t.table_name::text from information_schema.tables t
  where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
  order by t.table_name
$$;
revoke execute on function public.backup_table_names() from public, anon, authenticated;

-- Nightly at 22:00 UTC, which is 3 am in Pakistan. Supabase only.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.unschedule('backup_to_s3') where exists (select 1 from cron.job where jobname = 'backup_to_s3');
    perform cron.schedule('backup_to_s3', '0 22 * * *', $cron$
      select net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets where name = 'backup_url'),
        headers := jsonb_build_object('content-type', 'application/json',
                                      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
        body := '{}'::jsonb,
        timeout_milliseconds := 300000)
    $cron$);
  end if;
end $$;
