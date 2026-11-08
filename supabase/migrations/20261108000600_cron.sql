-- Every minute, ask the Edge Function to deliver due alerts. Only runs where
-- pg_cron and pg_net exist (Supabase). Local test databases skip it.
-- The function URL and secret are read from Vault so nothing is hard coded here:
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/run_due_notifications', 'notify_url');
--   select vault.create_secret('<random>', 'cron_secret');
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.unschedule('run_due_notifications') where exists (select 1 from cron.job where jobname = 'run_due_notifications');
    perform cron.schedule('run_due_notifications', '* * * * *', $cron$
      select net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets where name = 'notify_url'),
        headers := jsonb_build_object('content-type', 'application/json',
                                      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
        body := '{}'::jsonb)
    $cron$);
  end if;
end $$;
