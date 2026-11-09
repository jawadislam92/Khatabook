# Handoff: state of Duebook on 10 November 2026

This document lets a new Claude Code session, or a person, continue without the original conversation. Everything here was true when written. Secrets are named, never written out.

## 1. What exists

| Piece | Where | State |
|---|---|---|
| Flutter app, phases 0 to 4 | `app/` | Built, analyzer clean, 59 tests pass. Ledger, groups, jobs with alerts, invoicing with PDF, payments, business details, Bills tab, items report. |
| Database | `supabase/migrations/` (9 files) | Applied to dev and prod. SQL tests in `supabase/tests/` (6 files) all pass. |
| Edge Functions | `supabase/functions/` | `run_due_notifications` (push via FCM HTTP v1, in app inbox, health GET) and `backup_to_s3` (nightly dump to the owner's bucket). Deployed on dev and prod with JWT verification off; the `x-cron-secret` header is the gate. |
| Cron | pg_cron on both projects | Alerts every minute on both. Backup at 22:00 UTC on prod only. Vault holds `notify_url`, `backup_url`, `cron_secret`. |
| Public pages | `docs/web/` | Live at https://duebook.sparkingasia.com and `/privacy.html` on the owner's Hostinger account (folder `public_html/duebook` of sparkingasia.com). Uploaded by hand. |
| CI | `.github/workflows/ci.yml` | SQL tests on Postgres 16 and Flutter analyze, format, test, debug APK. Artifacts only on `main` now. |
| Release and deploy workflows | `release.yml`, `supabase-deploy.yml`, `check-secrets.yml` | Written and reading repository secrets, but none of the 12 secrets exist yet, so they have never run successfully. |
| APKs | gitignored at repo root in the cloud session only | `duebook-preview.apk` (sample data), `duebook-dev.apk`, `duebook-prod.apk` (push enabled). Rebuild locally with the commands below. |

Branch: everything is on `claude/khatabook-field-service-plan-7dg24c`. There is no `main` yet. When you create `main`, point the Hostinger upload note and the CI artifact condition at it.

## 2. Environments and public identifiers

| Thing | Value |
|---|---|
| Supabase dev project | `khatabook-dev`, ref `jepcsftdjejjzhfjnavy`, URL `https://jepcsftdjejjzhfjnavy.supabase.co`, region ap-south-1 |
| Supabase dev publishable key | `sb_publishable_oTLjMBC0q95QkO2UrJEaSg_-IkMyi0C` |
| Supabase prod project | `khatabook-prod`, ref `ohrnkvzemgfrxcuknamh`, URL `https://ohrnkvzemgfrxcuknamh.supabase.co`, region ap-south-1 (Mumbai) |
| Supabase prod publishable key | `sb_publishable_LQIHmZXNQ84ck5X3fKb6iw_HKjDceT3` |
| Firebase project | `duebook-1acb5`, Android app package `com.sparkingasia.duebook` |
| Google Cloud project for sign in | the same `duebook-1acb5` (shown as "Duebook" in the picker) |
| Web address | `duebook.sparkingasia.com` (DNS and hosting on Hostinger, under the sparkingasia.com website) |
| S3 backups | bucket `duebook-backups`, prefix `duebook/ohrnkvzemgfrxcuknamh/` |
| Deep links | `com.sparkingasia.duebook://login-callback` (auth), `https://duebook.sparkingasia.com/join/<code>` (invites, app link verification not yet published) |

### Secrets, by name and place (values are never in the repo or in chat)
- Supabase Edge Function secrets, both projects: `CRON_SECRET`, `FCM_SERVICE_ACCOUNT` (the Firebase service account JSON, key id starts `b2777b`), `BACKUP_S3_ACCESS_KEY`, `BACKUP_S3_SECRET_KEY`. Prod also has `BACKUP_S3_BUCKET`, `BACKUP_S3_REGION`.
- Supabase Vault, both projects: `notify_url`, `backup_url`, `cron_secret`.
- GitHub repository secrets (all MISSING as of now): `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `GOOGLE_SERVICES_JSON`, `SUPABASE_URL_PROD`, `SUPABASE_ANON_KEY_PROD`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF_DEV`, `SUPABASE_PROJECT_REF_PROD`, `SUPABASE_DB_PASSWORD_DEV`, `SUPABASE_DB_PASSWORD_PROD`. The "Check secrets" workflow (manual run) prints set or MISSING for each.
- Google OAuth client "Duebook Supabase" (Web application) with both Supabase callback URLs; its Client ID and secret are pasted into Authentication, Providers, Google on both projects. The consent screen is still in Testing (test users only) until the owner adds the home page and privacy links on the Branding page and presses Publish app.
- A Supabase personal access token named `claude-duebook` was created by the owner for the cloud session and saved as a network secret on the owner's Claude cloud "Default" environment. The owner can revoke it at supabase.com/dashboard/account/tokens. A local session does not need it; use `supabase login`.
- A Firebase service account key with id starting `f7f90b` passed through chat on 9 November and must be deleted in Google Cloud (IAM, Service accounts, firebase-adminsdk, Keys). Not yet confirmed deleted.

### Supabase Auth settings (set on both projects through the management API)
- Site URL: `https://duebook.sparkingasia.com`
- Redirect allow list: `com.sparkingasia.duebook://login-callback`, `https://duebook.sparkingasia.com/**`
- Email and password on, confirm email on (default SMTP, low rate limit), Google on.

### Test data
- Prod: the owner's account (Google), spaces "Personal" and "Junn" (a group with business enabled), one customer each, two entries, one job. Wipe before real launch if wanted.
- Dev: the owner's email account, plus a QA account `duebook-qa-1@sparkingasia.com` created directly in `auth.users` for automated walk throughs, with space "QA Biz", one customer and one job. Set a new password for it from the Supabase dashboard (Authentication, Users) before using it locally; the old one lived only in the cloud session.

## 3. Pending work, in priority order

### Fixes found on 9 and 10 November, not yet done
1. **Screens swallow errors.** Many screens use `ref.watch(provider).value ?? CircularProgressIndicator()`, so a failed or stalled request shows a spinner forever (seen on the Jobs tab and the job detail on the owner's phone). Replace with `.when(data:, loading:, error:)` showing `errorGeneric` plus a Retry that invalidates the provider. Start with `job_detail_screen.dart`, `business_home_screen.dart` tabs, `space_home_screen.dart`, `invoice_screen.dart`, `finish_job_screen.dart`, `bill_screen.dart`.
2. **No request timeouts.** supabase_flutter has none by default; a dropped Wi‑Fi connection leaves futures pending. Wrap the client with an `http.Client` that applies a 30 second timeout, or add `.timeout()` in the repositories.
3. **Client error reporting.** Add a small `client_errors` table (insert only for the signed in user, select for nobody but the service role) and a Riverpod `ProviderObserver` plus `FlutterError.onError` hook that records message, screen, app version. Lets you read phone side failures from the database instead of asking for screenshots.
4. **Preliminary audit findings (unverified, from an automated sweep that was still running when the session moved):**
   - `jobs_repository.dart` `saveItem()` sends `cost_price_paisa` on every update, so a manager editing a catalog item (who cannot see cost) erases the owner's cost price. Omit the column unless the caller may see costs.
   - `registerDevice()` upserts `devices` on `fcm_token`; when a second account signs in on the same phone the row belongs to the first user and RLS rejects the upsert, so the first account keeps receiving alerts. Fix with a SECURITY DEFINER RPC `register_device` that deletes other users' rows for that token and upserts. Also remove the row on sign out.
   - Realtime on `job_assignees` changes does not refresh the jobs list reliably; make `set_job_assignees` bump `jobs.updated_at` so the `jobs` subscription fires.
   - Viewer role sees every write button in the ledger; RLS rejects the inserts and two call sites have no error handling. Gate the UI on `myRole`.
   - `invoice_prefix` has a check constraint of 1 to 8 characters; the business details form has no `maxLength`.
   - "Leave group" is offered to the sole owner; `protect_last_owner` rejects it. Hide the button or explain.
   - `Entry.wasEdited` treats a void as an edit because `updated_at` moves on void. Exclude voided rows.
   The three lenses not finished were: views, realtime and Edge Function payloads; screens that never show an error; auth and deep links (password reset recovery flow, invite link handling, device token on sign out). Rerun those checks.
5. **Late tag timing.** Jobs show "Late" 30 minutes after their time. The owner may want 15. One constant in `job_card.dart`.

### Owner side items still open (see `docs/STEP_BY_STEP.md`)
- Delete the old Firebase key `f7f90b` in Google Cloud.
- Put the two links on the Google Branding page, add `sparkingasia.com` as an authorised domain, publish the consent screen. Until then only listed test users can use Google sign in.
- Android signing key (Step 7) before the first Play Store build. The GitHub secrets are only needed if releases should build on GitHub; APKs can also be built locally.
- Google Play Console account (Step 8).
- Old CI artifacts over the 500 MB allowance expire by 15 November; CI runs may fail until then, or delete them under Actions, Management, Artifacts.

### Phase 5 (from `docs/PLAN.md`)
Public invoice link for customers, logo on the bill, job photos, offline queue, security review against the checklist in `docs/TECHNICAL.md`, backup restore drill, help screens, Play Store internal testing then production, Roman Urdu if wanted, iOS if anyone needs it. Also: publish `/.well-known/assetlinks.json` on duebook.sparkingasia.com with the release signing certificate SHA-256 and set `autoVerify="true"` on the `/join/` intent filter in `AndroidManifest.xml`.

## 4. Build and test locally

### One time setup
1. Install Flutter 3.47.9 stable (the version CI pins). Android Studio with the Android SDK and command line tools, JDK 17 (bundled). Run `flutter doctor` and accept licenses with `flutter doctor --android-licenses`.
2. Clone the repository and run, inside `app/`: `flutter pub get` then `flutter gen-l10n`.
3. Download `google-services.json` from Firebase console (Project settings, Your apps, the Android app) and place it at `app/android/app/google-services.json`. It is gitignored. Needed only for builds with push.
4. For the SQL tests you need a Postgres 16 server: `docker run -d --name pg16 -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:16`, or a local install.
5. For the web walk through: Node 18+, then in `app/`: `npm init -y && npm i playwright && npx playwright install chromium`.
6. Supabase CLI for deploys: install, `supabase login`, then `supabase link --project-ref <ref>` per project when needed.

### Checks before any APK
```
cd app
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
cd ..
supabase/tests/run_local.sh postgresql://postgres:postgres@localhost:5432/postgres
```

### APK builds (release mode works without a keystore; it falls back to the debug key, fine for testing)
```
cd app
# sample data, no backend
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk ../duebook-preview.apk

# dev backend, push on
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://jepcsftdjejjzhfjnavy.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_oTLjMBC0q95QkO2UrJEaSg_-IkMyi0C \
  --dart-define=FIREBASE_ENABLED=true
cp build/app/outputs/flutter-apk/app-release.apk ../duebook-dev.apk

# prod backend, push on
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://ohrnkvzemgfrxcuknamh.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_LQIHmZXNQ84ck5X3fKb6iw_HKjDceT3 \
  --dart-define=FIREBASE_ENABLED=true
cp build/app/outputs/flutter-apk/app-release.apk ../duebook-prod.apk
```
All three builds share the package name, so installing one replaces another on the phone.

### Live walk through against dev (the way the cloud session checked the app)
```
cd app
flutter build web --release \
  --dart-define=SUPABASE_URL=https://jepcsftdjejjzhfjnavy.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_oTLjMBC0q95QkO2UrJEaSg_-IkMyi0C
python3 -m http.server 8099 --directory build/web &
node tool_live_check.js /tmp/live http://localhost:8099/ build/web/canvaskit <qa email> <qa password>
```
It signs in, creates or opens the "QA Biz" space, creates a job, opens it from the list, and prints every request and any 4xx body. `tool_screenshots.js` does the same against the sample data build for documentation screenshots.

### Database changes
1. Add `supabase/migrations/<yyyymmdd>000<n>_<name>.sql` and a `supabase/tests/<nn>_<name>_test.sql` following the existing pattern (`test.new_user`, `test.login`, `test.check`).
2. Run the SQL suite locally.
3. Apply to dev, then prod: `supabase link --project-ref <ref> && supabase db push`. If you apply SQL by hand instead, also insert the version into `supabase_migrations.schema_migrations`, or `db push` will complain later.
4. After DDL that adds relationships, confirm PostgREST sees them: a `GET /rest/v1/<table>?select=*,<embed>&limit=1` with the publishable key returns 401 "permission denied" (relationship found, RLS blocks anon) rather than 400 PGRST200.

### Edge Functions
`supabase functions deploy run_due_notifications` and `supabase functions deploy backup_to_s3`; `supabase/config.toml` pins `verify_jwt = false` for both. Health check: `GET` the function URL with header `x-cron-secret` set to the secret; it answers `fcm_configured`, `fcm_project`, `fcm_key_id` (prefix) and the names of configured secrets, never values. To send a test alert, insert a row into `scheduled_notifications` with `kind = 'reminder_due'`, `due_at = now()`, `recipients = array[<user id>]`, `payload = '{"title": "..."}'`; the next cron tick delivers it and sets `sent_at` or `last_error`.

## 5. Things learned the hard way
- PostgREST embeds need a foreign key inside the `public` schema. Columns that reference `auth.users` cannot be embedded as `profiles`; migration `20261109000200` added the extra keys to `profiles`. Any new "who did it" column the app wants to show needs the same.
- A new Supabase project ships the `supabase_realtime` publication empty. Tables the app listens to must be added (`entries`, `parties`, `jobs`, `job_assignees`, `invoices` are in now).
- New Supabase projects default the Site URL to `http://localhost:3000`; OAuth returns land there until the app's deep link is on the redirect allow list.
- The Preview repositories hide backend mismatches. Only the live walk through or a phone finds them.
- Private repositories on the GitHub free plan have 500 MB of artifact storage; uploading a 100 MB debug APK per push fills it in a week and GitHub then silently refuses to start one job per run.
- GitHub "environments" are not available on private free plan repositories; workflows must use repository secrets.
- `1 << 62` overflows in dart2js; use `math.max`. PDF Urdu needs Noto Naskh Arabic, not Nastaliq, because the pdf package shapes Arabic with presentation forms.
- Google requires a home page and a privacy policy on an authorised domain before an OAuth consent screen can be published.
