# Duebook, notes for Claude Code sessions

Read `docs/HANDOFF.md` first. It holds the full state of the project, the environments, what is live, what is pending, and how to build and test. `docs/CHAT_LOG.md` is the condensed record of the conversation that produced this repository.

## What this is
A Flutter app with a Supabase backend. Family and personal ledgers (khatabook) with a simple mode for elders, shared groups, and a business workspace for a CCTV and solar installer: jobs with team alerts, items used, invoice on the spot, unpaid invoices becoming customer udhaar. English and Urdu. Package `com.sparkingasia.duebook`.

## Layout
- `app/` Flutter 3.47 app. Riverpod 3, go_router, supabase_flutter. Screens under `lib/features/<area>/`, each with a `*_repository.dart` holding a `Supabase*Repository` (real) and a `Preview*Repository` (in memory, used when no `SUPABASE_URL` define is set).
- `supabase/migrations/` the database, applied in filename order. `supabase/tests/` SQL tests, `run_local.sh` runs everything against a throwaway Postgres. `supabase/functions/` Deno Edge Functions (`run_due_notifications`, `backup_to_s3`, shared code in `_shared/`).
- `docs/` plan, technical design, decisions, the owner's step by step setup, handoff. `docs/web/` the public pages served at duebook.sparkingasia.com.
- `.github/workflows/` CI (SQL tests, analyze, test, debug APK), release, Supabase deploy, secrets check.

## Rules that matter
- Never commit secrets: no `google-services.json`, no Firebase service account key, no keystore, no access tokens. `.gitignore` covers the usual files; keep it that way. Public values (Supabase URLs, publishable keys) are fine in docs.
- Every change to the database is a new migration file plus a test in `supabase/tests/`; apply it to dev first, then prod, and add the version to `supabase_migrations.schema_migrations` if applying by hand.
- Every screen that loads data must show the generic error with a retry when the request fails. Do not use `ref.watch(provider).value ?? spinner` for new screens; use `.when(...)`.
- The owner is not a developer. Write to them in plain, direct language, step by step, one click per step when guiding through a console. No em dashes, no filler, no AI sounding phrasing. Urdu strings live in `app/lib/l10n/app_ur.arb`; every new string needs both languages.
- Before handing over an APK, run `flutter analyze --fatal-infos`, `flutter test`, the SQL suite, and the live walk through (`app/tool_live_check.js`) against dev.

## Quick commands
See the "Build and test" section of `docs/HANDOFF.md` for the exact commands, defines and keys.
