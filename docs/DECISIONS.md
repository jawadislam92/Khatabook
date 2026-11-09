# Decisions

Locked on 8 November 2026. Each one can be revisited, but the code follows these until we agree otherwise.

| # | Decision | Choice |
|---|---|---|
| 1 | Login | Email and password or Google sign in to set up the account. PIN or fingerprint for daily use. Phone number recorded on the profile for contact matching. SMS login can be added later. |
| 2 | Languages | English and Urdu from the start. Roman Urdu in phase 5. |
| 3 | Platforms | Android first. iOS from the same code once Android is stable. |
| 4 | Installer price editing | Quantities only. Prices locked, with a per item "allow price edit" switch for things like labour. |
| 5 | Invoice approval | Invoices go to the customer as soon as the installer shares. The owner is notified and can issue a corrected invoice. |
| 6 | Tax on invoices | A tax line exists but is off by default. |
| 7 | Family dashboard scope | Only shared family books. Personal ledgers stay personal unless a member shares a book. |
| 8 | Backend | Hosted Supabase, not the VPS. Nightly backups to the owner's S3 bucket. |
| 9 | App stack | Flutter, Riverpod, go_router, Drift for local data, Supabase Flutter SDK, Firebase Cloud Messaging. |
| 10 | Money | Stored as integer paisa everywhere. Displayed in rupees with Pakistani digit grouping (12,34,567). |

## Placeholders waiting on the owner

These are set to working defaults so the build can proceed. Changing them is cheap until the Firebase project and Play Store listing are created.

| Item | Current default | Change by |
|---|---|---|
| App name | **Duebook** (decided 8 Nov 2026) | Settled |
| Android package name | `com.sparkingasia.duebook` (domain confirmed: sparkingasia.com) | Before creating the Firebase Android app |
| Palette | Teal `#0E8C7F`, blue, saffron `#F59E0B`, indigo, one hue per space kind | Any time |
| Business name, address, payment details, terms, tax | Entered in the app: Bills tab, Business details | Any time |
| Business logo on the bill | Not yet (phase 5, with the public invoice link) | Phase 5 |
| Item catalog | Entered in the app: Catalog tab | Any time |
| Who sees cost prices | Owner only | Any time, it is a space setting |

## Infrastructure created on 8 November 2026

| Item | Value |
|---|---|
| Supabase organisation | sparkingasia |
| Development project | `khatabook-dev`, ref `jepcsftdjejjzhfjnavy`, Mumbai, URL https://jepcsftdjejjzhfjnavy.supabase.co |
| Production project | `khatabook-prod`, ref `ohrnkvzemgfrxcuknamh`, Mumbai, URL https://ohrnkvzemgfrxcuknamh.supabase.co |
| Migrations | Foundation to jobs applied 8 Nov 2026, invoices applied 9 Nov 2026, both dev and prod, through the Supabase connector. Later migrations go through the pipeline. |
| Edge Functions | `run_due_notifications` (every minute) and `backup_to_s3` (22:00 UTC, 3 am Pakistan) deployed on both projects; pg_cron schedules active. |
| Backups | S3 bucket `duebook-backups`, region ap-south-1, nightly from prod. |

Publishable keys are in `app/.env.example`. They are public by design; row level security does the protecting.
