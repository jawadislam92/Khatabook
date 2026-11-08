# Technical Plan

How we build what [PLAN.md](PLAN.md) describes. Covers the stack, the architecture, the database, the security plan, notifications, offline support, testing, and running costs.

---

## 1. Stack

| Layer | Choice | Why |
|---|---|---|
| Mobile app | **Flutter** (Dart), Android first, iOS from the same code | One codebase. Text scaling, right to left layout for Urdu, and large touch targets are built in. Mature packages for PDF generation, sharing, secure storage, biometrics, local database. |
| Backend | **Supabase** (hosted Postgres, Auth, Storage, Realtime, Edge Functions, scheduled jobs) | Security is enforced inside the database with Row Level Security, so there is no API layer to get wrong. Almost no server code to maintain. Free tier covers a family and a small business. Can be self hosted later if ever needed. |
| Push notifications | **Firebase Cloud Messaging** (FCM), sent from Supabase Edge Functions | Free, reliable on Android, works on iOS too. |
| Scheduled notifications | **pg_cron** inside Supabase calling an Edge Function every minute | Reminders and job alerts fire on time without a separate server. |
| PDF | Generated on the phone with the `pdf` and `printing` packages, uploaded to Supabase Storage for shareable links | Instant, works offline, one code path for statements and invoices. |
| Sharing | Native share sheet (`share_plus`) so WhatsApp, SMS, email all work with no API cost | The official WhatsApp Business API is expensive and needs approval. The share sheet costs nothing. |
| Local database | **Drift** (SQLite) with SQLCipher encryption | Offline reads and an outbox for offline writes. |
| State management | Riverpod | Simple, testable, widely used. |
| CI | GitHub Actions: analyze, test, build APK on every push to main, signed release build on tags | Nobody needs Android Studio to get a build. |

Alternatives weighed:
- **React Native with Expo** instead of Flutter. Would work. Flutter chosen for tighter control of layout and text scaling, and better offline database options.
- **Firebase Firestore** instead of Supabase. Firestore security rules are harder to review than SQL policies, and the reports (revenue by month, items used, unpaid ageing) are plain SQL queries in Postgres but painful in Firestore.
- **Custom Node or Django backend.** More code, more to secure, more to host. Not justified at this scale.

---

## 2. Architecture

```
  Phone (Flutter)
  +------------------------------------------------------+
  |  UI (feature screens, simple mode theme)              |
  |  State (Riverpod)                                     |
  |  Repositories  <---->  Local DB (Drift, encrypted)    |
  |        |                   |  outbox (pending writes) |
  |        v                   v                          |
  |  Sync engine: push outbox, pull changes since cursor  |
  |  Secure storage (session tokens, PIN hash)            |
  +--------------------------+---------------------------+
                             | HTTPS (TLS), JWT per user
                             v
  Supabase project
  +------------------------------------------------------+
  |  Auth (email/password, Google, optional phone OTP)    |
  |  PostgREST API  ->  Postgres with RLS on every table  |
  |  Storage buckets (private): attachments, invoices     |
  |  Edge Functions: accept_invite, create_invoice,       |
  |     send_push, run_due_notifications, share_link      |
  |  pg_cron: every minute -> run_due_notifications       |
  |  Triggers: audit log, balance views, invoice numbers  |
  +--------------------------+---------------------------+
                             |
                             v
  Firebase Cloud Messaging -> phones
```

Rules of the architecture:
- The app talks to Postgres through Supabase using the user's own JWT. Row Level Security decides what each user can read or write. There is no "admin" path from the app.
- Anything that must be trusted (invoice numbering, accepting an invite, sending a push, creating a share link) runs in an Edge Function that re checks permissions server side.
- The service role key (which bypasses RLS) exists only inside Edge Functions and CI secrets. It never ships in the app.

---

## 3. Repository layout

```
khatabook/
  app/                         Flutter project
    lib/
      core/                    theme, simple mode, i18n, routing, utils (money, number to words)
      data/                    Drift tables, Supabase client, sync engine, repositories
      features/
        auth/
        spaces/                spaces list, members, invites, roles
        ledger/                parties, entries, balances, reminders, statements
        jobs/                  customers, jobs, statuses, today board, my jobs
        invoices/              catalog, finish job flow, invoice PDF, payments
        notifications/
        settings/
      main.dart
    test/                      unit and widget tests
    integration_test/
  supabase/
    migrations/                SQL: tables, RLS policies, triggers, views
    functions/                 Edge Functions (TypeScript)
    tests/                     SQL tests for RLS (member of A cannot see B)
    seed.sql                   demo data for development
  docs/                        these documents
  .github/workflows/           ci.yml, release.yml
```

---

## 4. Data model

Money is stored as integers in paisa (Rs 1 = 100 paisa). No floating point anywhere near money.

All tables have `id uuid`, `created_at`, `updated_at`, `created_by`. Most have `deleted_at` for soft delete.

### Identity and spaces

| Table | Key columns | Notes |
|---|---|---|
| `profiles` | user_id, display_name, phone_hash, language, simple_mode, avatar_path | One per auth user. Phone stored as a salted hash for contact matching. |
| `spaces` | name, kind (personal, group), business_enabled, settings jsonb (invoice approval, price edit rules, tax) | A personal space is created by trigger on signup. |
| `space_members` | space_id, user_id, role (owner, manager, member, viewer), joined_at | The table every RLS policy checks. |
| `invites` | space_id, token_hash, role, phone_hash (optional), expires_at, used_at, created_by | Single use, 48 hour expiry. |
| `devices` | user_id, fcm_token, platform, last_seen_at | Push targets. |

### Ledger

| Table | Key columns | Notes |
|---|---|---|
| `books` | space_id, name, locked_until (date) | "Home", "Committee". Month lock. |
| `parties` | space_id, name, phone_hash, phone_display, photo_path, linked_user_id, is_customer, address, geo_lat, geo_lng, notes | Customers are parties with `is_customer = true` and address fields. |
| `entries` | book_id, party_id, direction (gave, got), amount_paisa, entry_date, note, created_by, source_type (manual, invoice, payment), source_id, reversal_of, voided_at | Append only. A delete inserts a reversal and sets `voided_at` on the original. |
| `entry_attachments` | entry_id, storage_path, mime, size | Private bucket. |
| `reminders` | party_id, due_date, note, done_at | |
| `party_balances` (view) | party_id, balance_paisa | Sum of non voided entries. Positive means they owe us. |

### Business

| Table | Key columns | Notes |
|---|---|---|
| `items` | space_id, name_en, name_ur, unit, sale_price_paisa, cost_price_paisa, category, is_favourite, allow_price_edit, active | Cost price readable only by owner and, if allowed, manager (column level grant via a view). |
| `jobs` | space_id, customer_id, title, job_type, scheduled_at, address, geo, notes, estimate_paisa, status, created_by | Status enum: scheduled, confirmed, on_the_way, working, finished, invoiced, paid, cancelled. |
| `job_assignees` | job_id, user_id, confirmed_at | |
| `job_events` | job_id, event_type, from_status, to_status, actor_id, note, created_at | Full status history. |
| `job_photos` | job_id, storage_path, kind (before, after) | |
| `job_items` | job_id, item_id, qty, unit_price_paisa, note | What was used. Snapshot of price at the time. |
| `invoices` | job_id, space_id, number, issued_at, customer_id, subtotal, discount, tax, total, received_paisa, balance_paisa, status (draft, pending_approval, issued, paid, void), pdf_path, terms_text | Number assigned by an Edge Function using a per space counter, so there are never gaps or duplicates. |
| `invoice_lines` | invoice_id, description, qty, unit_price_paisa, amount_paisa | Frozen copy of job_items at issue time. |
| `payments` | invoice_id, customer_id, method (cash, bank, easypaisa, jazzcash, other), amount_paisa, paid_at, note, recorded_by | Trigger updates invoice balance and inserts a ledger entry. |
| `share_links` | invoice_id, token_hash, expires_at, revoked_at, view_count | Public invoice link, 30 day default. |

### Notifications

| Table | Key columns | Notes |
|---|---|---|
| `scheduled_notifications` | due_at, kind, job_id or reminder_id, recipient_user_ids, payload jsonb, sent_at, cancelled_at | Rows created when a job is created or rescheduled: immediate, plus 30 minutes unconfirmed check, evening before, one hour before. Rescheduling cancels and recreates. |
| `notifications` | user_id, title, body, deep_link, read_at | In app inbox. |
| `audit_log` | table_name, row_id, action, actor_id, old_row jsonb, new_row jsonb, at | Filled by triggers on every sensitive table. |

### How the invoice and the ledger stay in sync

1. Issuing an invoice with a balance due inserts an `entries` row: direction `gave` (we gave goods and work on credit), amount = balance, `source_type = invoice`.
2. Recording a payment inserts an `entries` row: direction `got`, amount = payment, `source_type = payment`, and updates `invoices.balance_paisa`.
3. Voiding an invoice inserts reversal entries. Nothing is ever deleted.

So the customer's ledger balance is always the sum of unpaid invoice balances plus any manual entries, and the two views can never disagree.

---

## 5. Security plan

Honest framing first: no system can be made impossible to attack. What we can do is make every layer hard to get through, make sure that getting through one layer does not expose everything, and make sure we would notice. The plan below follows the OWASP Mobile Application Security standard (MASVS) and standard Postgres hardening.

### 5.1 Accounts and sessions

- Supabase Auth. Email and password with a minimum of 10 characters and a breached password check, plus Google sign in. Phone OTP can be enabled later.
- Two factor (authenticator app) available to everyone and required for space owners with business enabled.
- Login rate limited by Supabase. Lockout after repeated failures.
- Session tokens kept in Android Keystore or iOS Keychain through `flutter_secure_storage`, never in plain files or shared preferences.
- Short lived access tokens (1 hour) with refresh rotation. "Sign out everywhere" button in settings revokes all sessions.
- A list of logged in devices with last seen time, and the ability to remove one.

### 5.2 Authorisation (who can see what)

- Row Level Security on every table, no exceptions. Each policy joins through `space_members` and checks the role.
- Column protection: cost prices are exposed through a view that returns null unless the user's role is owner (or manager when the space setting allows).
- Writes that need trust go through Edge Functions which verify the JWT and re check the role before using the service key.
- RLS policies have automated tests: user in space A cannot read, insert, update, or delete anything in space B; a viewer cannot write; a member cannot change roles; nobody can edit an entry in a locked month.

### 5.3 Data in transit and at rest

- TLS 1.2 or higher only. Certificate pinning to the Supabase project host, with a remote kill switch so a certificate rotation cannot brick the app.
- Database and storage encrypted at rest by Supabase.
- Attachments and invoice PDFs live in private buckets. The app gets short lived signed URLs (minutes). Public invoice links go through an Edge Function that checks the token, the expiry, and the revoked flag, then streams the file.
- Local SQLite database encrypted with SQLCipher, key held in the Keystore.

### 5.4 On the device

- App lock with PIN or biometrics, auto lock after a configurable time in the background. PIN stored as a salted hash, verification rate limited.
- Sensitive screens set the secure flag so they do not appear in the recent apps switcher or screenshots (optional per user, since elders may want screenshots of a statement).
- Root or jailbreak detection shows a warning and disables biometric unlock, but does not block the app.
- No secrets in the binary. The anon key is public by design and useless without passing RLS. Release builds use R8 obfuscation and resource shrinking.
- Clipboard is not used for amounts or tokens.

### 5.5 Integrity and tamper evidence

- Append only ledger. Every change is a new row or a reversal, so history cannot be rewritten.
- Audit log triggers on entries, invoices, payments, members, items, and space settings, recording who, what, old and new.
- Month lock enforced in the database, not only in the UI.
- Invoice numbers assigned server side in a transaction. Invoice lines are frozen copies, so later catalog price changes do not alter old invoices.

### 5.6 Abuse and input

- Invite tokens are 32 random bytes, stored hashed, single use, 48 hour expiry, bound to a phone hash when sent to a specific person.
- Edge Functions rate limited per user and per IP.
- Uploads checked for type and size (images up to 5 MB, PDFs we generate ourselves). Images re encoded on the phone before upload to strip metadata and malicious payloads.
- All text that goes into a PDF is escaped. All queries go through PostgREST or parameterised SQL, so there is no string built SQL.
- Deep links from notifications are validated against an allow list before navigation.

### 5.7 Operations

- Two Supabase projects: development and production. No real data in development.
- Secrets live in GitHub Actions secrets and Supabase function secrets. The repository has a secret scanning check in CI.
- Dependencies pinned and scanned (Dart `pub outdated`, Dependabot, `npm audit` for Edge Functions).
- GitHub Actions pinned to commit hashes.
- Backups: daily automated database backup. On the free tier we run our own nightly `pg_dump` to a private bucket from a scheduled Edge Function. Point in time recovery if we move to the Pro plan. A documented restore drill before production launch.
- Monitoring: auth logs reviewed for failed login spikes, Edge Function error alerts to the owner's email.
- Incident plan written down: rotate keys, force sign out everywhere, restore from backup, inform members.
- Play App Signing, with the upload key stored offline.

### 5.8 Privacy

- Minimum data: name, phone (hashed, plus a display copy the user chose to store), language. No contact list uploaded; matching is done by hashing numbers on the phone and comparing hashes.
- A "delete my account" flow that anonymises the profile and removes personal spaces while keeping shared ledger rows attributed to "Removed member" so other people's books stay correct.
- Analytics off by default. Crash reporting on, with no personal data in the reports.

### 5.9 Threats we planned for

| Threat | What stops it |
|---|---|
| Phone stolen while unlocked | App lock with auto lock, sign out everywhere from another device, data encrypted locally |
| Someone extracts the anon key from the APK | Key is public by design, RLS blocks every row they are not a member of, rate limits slow brute forcing |
| A family member with Member role edits or deletes entries to hide something | Append only ledger, audit log, activity feed, month lock, role limits |
| Installer inflates prices | Price edit disabled per item, every change audited, owner notified on every invoice |
| Phishing with a fake invite link | Links are single use, expire, and show the inviting person's name and space before joining |
| Old invoice link forwarded around | Expires in 30 days, revocable, view count visible to owner |
| Supabase project credentials leak | Service key only in functions and CI, rotation procedure documented, 2FA on the Supabase account itself |
| Lost phone, no backup | Data is in the cloud, nightly backups, restore drill done |

---

## 6. Notification engine

1. When a job is created, assigned, or rescheduled, a database trigger writes rows into `scheduled_notifications`:
   - now: "New job, tap to confirm" to each assignee
   - now + 30 min: "unconfirmed check" (skipped at send time if someone has confirmed)
   - 20:00 the evening before: tomorrow's digest (one row per space per day, de duplicated)
   - scheduled_at minus 60 min: reminder to assignees
2. `pg_cron` runs every minute and calls the `run_due_notifications` Edge Function.
3. The function selects due, unsent, uncancelled rows, builds the message in each recipient's language, sends through FCM to every device of each recipient, writes to the in app `notifications` inbox, and marks the row sent.
4. Status changes (confirm, on the way, finished, paid) call `send_push` directly from a trigger via `pg_net`, so the owner hears about them within seconds.
5. Notification actions: Android notifications carry a Confirm action button that calls a small Edge Function with the job id, so confirming does not even require opening the app.
6. Delivery fallback: if a notification for a job has not been opened or acted on in 30 minutes and the job is within 24 hours, the owner is told so he can phone the installer. SMS fallback can be added later for a per message cost.

---

## 7. Offline support

- Every read comes from the local Drift database. The app never shows a spinner for data it already has.
- Writes (entries, job status changes, items used, photos) are written locally and placed in an outbox. The sync engine sends them when the network returns, in order, with client generated UUIDs so retries are safe.
- Pull sync uses an `updated_at` cursor per table, so only changes come down.
- Conflicts are rare because the ledger is append only. For fields that can be edited (a note, a job time), the server timestamp wins and the audit log keeps both versions.
- Login, first sync, invite acceptance, and PDF link creation need a connection. Invoice PDF generation and WhatsApp sharing work offline because the PDF is made on the phone; the upload to storage happens when the network returns.
- Phase 1 ships with local caching and the outbox for entries. Full job and photo offline handling arrives in phase 5.

---

## 8. Localisation and accessibility

- Strings in ARB files for English and Urdu, with Roman Urdu as an optional third file. Flutter's `intl` for dates and numbers.
- Urdu uses a Nastaliq font (Noto Nastaliq Urdu) with a fallback to Naskh for small sizes where Nastaliq becomes hard to read.
- Digits default to Western numerals since bank statements and phone keypads use them. Option for Urdu digits.
- Number to words helper for Urdu and English, tested against a table of values (1, 10, 100, 1,000, 1,00,000, 10,00,000 with lakh and crore).
- Simple mode is a theme and layout mode, not a separate app: text scale 1.3, minimum touch target 56 dp, contrast ratio at least 7:1, simplified home and entry screens.
- Every tappable control has a semantics label for TalkBack and VoiceOver. Colour is never the only signal.
- Tested on a low end Android phone with the system font set to largest.

---

## 9. Testing

| Kind | What it covers |
|---|---|
| Unit tests | Balance arithmetic, reversal logic, invoice totals and rounding, number to words, date handling, outbox ordering |
| Widget tests | Simple mode layouts, right to left rendering, amount keypad, entry confirmation sentence |
| SQL tests for RLS | Cross space isolation, role limits, locked months, column protection for cost price. Run in CI against a fresh database with the migrations applied. |
| Edge Function tests | Invite acceptance, invoice numbering under concurrency, share link expiry |
| Integration tests | Create job, confirm from notification, finish with items, invoice created, ledger entry present, payment clears it |
| Manual device matrix | Android 8 low end, Android 13 mid range, largest system font, Urdu locale, airplane mode scenarios |

---

## 10. Environments and release

- `dev` Supabase project with seed data, `prod` with real data. Flutter flavours pick the right project at build time through `dart-define`.
- CI on every pull request: `flutter analyze`, `flutter test`, SQL tests, Edge Function tests.
- Tagged commits produce a signed release APK and App Bundle. Play Console internal testing track for the family and team first, production after phase 5.
- Database migrations are plain SQL files applied by the Supabase CLI, reviewed like code.

---

## 11. Running costs

| Item | Cost |
|---|---|
| Supabase free tier (500 MB database, 1 GB storage, 50,000 monthly users, 500,000 Edge Function calls) | Free. Enough for a family and a small business for a long time. |
| Supabase Pro, only if we want built in daily backups and point in time recovery, or more storage for photos | USD 25 a month |
| Firebase Cloud Messaging | Free |
| Google Play developer account | USD 25 once |
| Apple developer account, only if iOS | USD 99 a year |
| SMS login or SMS fallback, only if chosen | Per message, roughly PKR 2 to 5 each through a local gateway |
| Domain for invoice links (optional, nicer than a Supabase URL) | About USD 12 a year |
