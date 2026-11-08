# What You Need to Provide

Everything the build needs from your side, in the order it is needed. Secrets never get pasted into chat. They go into GitHub repository secrets or Supabase function secrets, and the build pipeline reads them from there. I only ever need the public values (project URL, bucket name, region, app name).

How to add a GitHub secret: repository page, Settings, Secrets and variables, Actions, New repository secret.

---

## A. Needed now (before phase 0 starts)

### 1. Answers to the decisions
Section 9 of [PLAN.md](PLAN.md). "Go with your recommendations" is a complete answer.

### 2. Supabase account and two projects (free)
1. Sign up at supabase.com with the business or family email. Turn on two factor on that account.
2. Create two projects: `khatabook-dev` and `khatabook-prod`. Region: Mumbai (closest to Pakistan with the lowest latency) or Singapore.
3. Save the database password for each project in your password manager.
4. Send me in chat (these are public, safe to share):
   - Project URL for each (looks like `https://xxxx.supabase.co`)
   - Project reference id for each (the `xxxx` part)
   - Anon key for each (Project Settings, API)
5. Add to GitHub secrets (never in chat):
   - `SUPABASE_ACCESS_TOKEN` (your account, Access Tokens page, create one named "github-ci")
   - `SUPABASE_DB_PASSWORD_DEV`, `SUPABASE_DB_PASSWORD_PROD`
   - `SUPABASE_PROJECT_REF_DEV`, `SUPABASE_PROJECT_REF_PROD`

With these the pipeline applies database migrations and deploys Edge Functions itself. You never run SQL by hand.

### 3. Firebase project (free), for push notifications
1. console.firebase.google.com, create project `khatabook`. Analytics off.
2. Add an Android app. Package name: we agree on this first, something like `pk.yourfamilyname.khatabook`. I will confirm the exact name before you do this step.
3. Download `google-services.json`. Add it to GitHub secrets as `GOOGLE_SERVICES_JSON` (paste the file contents).
4. Project Settings, Service accounts, Generate new private key. This JSON lets the server send pushes. Add it to Supabase function secrets on both projects as `FCM_SERVICE_ACCOUNT` (Supabase dashboard, Edge Functions, Secrets). Do not put it in GitHub.

### 4. AWS S3 bucket, for nightly off site backups
You already have one. Create a separate bucket or a folder just for this, for example `khatabook-backups`.
1. In IAM create a user `khatabook-backup` with a policy that allows only `s3:PutObject`, `s3:GetObject`, `s3:ListBucket` on that one bucket. Nothing else.
2. Turn on bucket versioning and block all public access.
3. Add the access key and secret key to Supabase function secrets on the prod project as `BACKUP_S3_ACCESS_KEY`, `BACKUP_S3_SECRET_KEY`.
4. Send me in chat: bucket name and region.

### 5. Business content for invoices
- Business name in English and Urdu
- Logo (PNG, transparent background, at least 1000 px wide)
- Address and phone numbers to print on the invoice
- Payment details to print: bank name, account title, account number or IBAN, EasyPaisa and JazzCash numbers
- Warranty or terms text, if any
- Job types the business does
- First item list: name, unit, sale price, and cost price if you want profit reports. A spreadsheet or even a photo of a price list is fine. A photo of a current handwritten bill helps me match the layout people are used to.

### 6. App identity
- App name as it will appear under the icon
- A colour you like, or a logo if you have one
- Package name (see step 3)

---

## B. Needed during the build (phases 1 to 4)

### 7. Test phones and testers
- Two or three Android phones that represent the real users, ideally one older or cheaper phone
- Gmail addresses of everyone who should receive test builds (family and the team). These go on the Play Console internal testing list.
- One person who reads Urdu well to review the Urdu strings

### 8. Google sign in (if chosen in the decisions)
Needs the SHA-1 fingerprint of the signing key (step 9 below) added in Firebase, then one toggle in Supabase Auth. I will walk you through the two clicks when we get there.

### 9. Android signing key
Generated once, kept forever. Losing it means you cannot update the app. Run this on your own computer, not on a shared one:

```
keytool -genkey -v -keystore khatabook-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then:
- Store `khatabook-upload.jks` and its password in your password manager and on one offline backup (USB drive)
- Add to GitHub secrets: `ANDROID_KEYSTORE_BASE64` (the file encoded with `base64 -w0 khatabook-upload.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`upload`), `ANDROID_KEY_PASSWORD`

### 10. Domain for invoice links (optional, recommended)
A subdomain such as `app.yourdomain.com` so invoice links look like yours instead of a Supabase URL. I need DNS access or someone who can add one CNAME record when asked.

---

## C. Needed at release (phase 5)

### 11. Google Play Console
- Register at play.google.com/console, one time USD 25
- Developer name shown on the store listing, a support email, and a short description
- A privacy policy page (I will write it, you host it on your existing hosting or the VPS)
- Enrol in Play App Signing when prompted (default, just accept)

### 12. Apple (only if iPhone users)
- Apple Developer Program, USD 99 a year
- A Mac is needed for the final upload step, or we use a cloud build service

---

## D. About the VPS and hosting you already have

**You do not need the VPS for this app.** The honest trade off:

| Option | Good | Bad |
|---|---|---|
| Hosted Supabase (recommended) | Their team patches the database, auth, and storage. Automatic TLS. Free at our scale. Point in time backups available on the paid plan. | Data sits in their cloud (Mumbai or Singapore region). Paid plan if we ever need more than the free limits. |
| Self hosted Supabase on your VPS | Full control, data on your own server. | You become responsible for OS updates, Postgres updates, firewall, TLS renewals, monitoring, disk space, and backups. One missed patch is how most small self hosted systems get broken into. Needs at least 4 GB RAM. |

Given that "nobody can attack it" is a goal, the hosted option is safer unless someone will look after the VPS every week. The design keeps the option open: Supabase is open source, and the same migrations and functions run on a self hosted copy if you decide to move later.

Useful jobs for the VPS and hosting you already have:
- Host the privacy policy page and a one page site for the app
- Host the invoice link subdomain if you prefer it off Supabase
- A second copy of the nightly backups, so backups live at Supabase, S3, and the VPS

Useful jobs for S3:
- Nightly off site database backups (step 4). Keeping backups with a different company than the database is good practice.
- Optionally, photos and invoice PDFs instead of Supabase Storage. Supabase Storage is simpler and already covered by the access rules, so I recommend starting there and only moving to S3 if the free 1 GB runs out.

---

## E. What you do not need to provide

- A developer machine or Android Studio. The pipeline builds the APK.
- Any server code. It is all written in this repository.
- Design files. I will design the screens in code, and you review on your phone.
- Any paid service until Play Store release (USD 25 once).
