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
| App name | Khatabook | Before store listing |
| Android package name | `pk.khatabook.app` | Before creating the Firebase Android app |
| Primary colour | Deep green `#1D7A4A` | Any time |
| Business name, logo, address, payment details | Sample values in seed data | Before phase 4 |
| Item catalog | Sample CCTV and solar items in seed data | Before phase 4 |
| Who sees cost prices | Owner only | Any time, it is a space setting |
