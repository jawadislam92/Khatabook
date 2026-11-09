# Your Steps, In Order

Plain instructions for the owner. Each step says what to do, where, and what to send me. Nothing secret is ever sent in chat.

Where secrets go: GitHub repository page, **Settings**, **Secrets and variables**, **Actions**, **New repository secret**. Type the name exactly as written below, paste the value, save.

---

## Step 1. Reply with three quick choices (2 minutes)

Send me in chat:

1. App name as it will appear under the icon. Default is **Khatabook**.
2. Android package name. Default is **com.sparkingasia.duebook**. If you own a domain, the usual form is the domain backwards plus the app, for example `com.sparkingasia.khatabook`.
3. Keep the colours you saw in the screenshots (teal and blue, saffron, indigo), or tell me the brand colours you want.

These must be settled before Step 3, because the Firebase app is tied to the package name.

## Step 2. Supabase, the database and login service (15 minutes, free)

1. Go to supabase.com and sign up with the email you want to own the system. Turn on two factor authentication in the account settings.
2. Click **New project**. Name: `khatabook-dev`. Region: **Mumbai** or **Singapore**. Set a strong database password and save it in your password manager.
3. Repeat for a second project named `khatabook-prod`.
4. For each project open **Project Settings**, then **API**. Copy the **Project URL** and the **anon public** key. Also note the **Reference ID** (the short code in the URL).
5. Send me in chat, for both projects: Project URL, anon key, Reference ID. These are public values.
6. In your Supabase account, open **Access Tokens** (under your profile) and create one named `github-ci`. Copy it once.
7. Add these GitHub secrets:
   - `SUPABASE_ACCESS_TOKEN` = the token from step 6
   - `SUPABASE_PROJECT_REF_DEV` = reference id of khatabook-dev
   - `SUPABASE_PROJECT_REF_PROD` = reference id of khatabook-prod
   - `SUPABASE_DB_PASSWORD_DEV` = database password of khatabook-dev
   - `SUPABASE_DB_PASSWORD_PROD` = database password of khatabook-prod
   - `SUPABASE_URL_PROD` = Project URL of khatabook-prod
   - `SUPABASE_ANON_KEY_PROD` = anon key of khatabook-prod

After this, the pipeline deploys the database itself and sign in works with real accounts.

## Step 3. Firebase, for push notifications (10 minutes, free)

Do this after Step 1 is settled.

1. Go to console.firebase.google.com with the same Google account. **Add project**, name `khatabook`, turn **off** Google Analytics.
2. On the project home, click the Android icon to add an app. Android package name: the one from Step 1. App nickname: Khatabook. Leave the SHA-1 empty for now.
3. Download `google-services.json`. Open it in a text editor, copy the whole content, and add it as the GitHub secret `GOOGLE_SERVICES_JSON`.
4. Click the gear icon, **Project settings**, **Service accounts**, **Generate new private key**. A JSON file downloads (named like `khatabook-xxxx-firebase-adminsdk-xxxx.json`). This one is powerful: do not put it in GitHub. Instead, in each Supabase project go to **Edge Functions**, **Secrets**, add `FCM_SERVICE_ACCOUNT` with the file's full content as the value.

   The two files are easy to mix up. `google-services.json` starts with `"project_info"` and goes to GitHub only. The service account key starts with `"type": "service_account"` and has `"private_key"` and `"client_email"` inside. Only that second file works in `FCM_SERVICE_ACCOUNT`; with the wrong file, alerts still appear in the in app inbox but no push arrives.
5. Tell me in chat that it is done. Nothing to send. I check it with the health call: the alert function answers `fcm_configured: true` once the right file is in place.

## Step 4. Your S3 bucket, for nightly backups (10 minutes)

1. In the AWS console open **S3** and create a bucket named something like `khatabook-backups` in the Mumbai region. Keep **Block all public access** on. Turn on **Bucket Versioning**.
2. Open **IAM**, **Users**, **Create user** named `khatabook-backup`. No console access.
3. Attach an inline policy that allows only `s3:PutObject`, `s3:GetObject`, `s3:ListBucket` on that bucket. If you are unsure how to write it, tell me the bucket name and I will send you the exact policy text to paste.
4. Create an access key for that user. Add both values as Supabase Edge Function secrets on the prod project: `BACKUP_S3_ACCESS_KEY` and `BACKUP_S3_SECRET_KEY`.
5. Send me in chat: the bucket name and region.

## Step 5. Business content for invoices (now done inside the app)

No need to send anything in chat. The owner or a manager fills this in once, on the phone:

1. Open the business space, tap the **Bills** tab, then the shop icon at the top right (**Business details**).
2. Fill in the business name in English and Urdu, tagline, address, phone, email.
3. Fill in the payment details that print on every bill: bank, account title, account number or IBAN, EasyPaisa, JazzCash. Only the ones you fill are printed.
4. Set the bill number prefix (default `INV`, so bills read `INV-2026-0001`), the terms line, and turn tax on only if you charge it.
5. The **Catalog** tab is where the item list lives: name, unit, sale price, cost price (owner only), and the quick tile switch for the things used on most jobs.

A logo upload comes in phase 5 together with the public invoice link.

## Step 6. Test phones and testers (before the first APK, during phase 1)

- Two or three Android phones, one of them old or cheap
- Gmail addresses of everyone who should get test builds
- Name of one person who reads Urdu well and can check the translations

## Step 7. Android signing key (once, before the first release build)

On your own computer with Java installed (it comes with Android Studio, or install a JDK), open a terminal and run:

```
keytool -genkey -v -keystore khatabook-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

It asks for a password and some names. Then:

1. Save `khatabook-upload.jks` and the password in your password manager and on a USB drive. Losing it means you cannot update the app on the Play Store.
2. Make the file into text: on Mac or Linux run `base64 -w0 khatabook-upload.jks` (on Mac just `base64 -i khatabook-upload.jks`), on Windows PowerShell run `[Convert]::ToBase64String([IO.File]::ReadAllBytes("khatabook-upload.jks"))`. Copy the output.
3. Add GitHub **repository** secrets (GitHub repo, Settings, Secrets and variables, Actions, Repository secrets, New repository secret. Not Environment secrets, not Variables, not Dependabot or Codespaces secrets): `ANDROID_KEYSTORE_BASE64` (the text from step 2), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (the word `upload`), `ANDROID_KEY_PASSWORD` (same as the keystore password unless you chose another).

## Step 8. Google Play Console (at release, USD 25 once)

1. Register at play.google.com/console with the Google account that should own the app.
2. Send me the developer name you chose and a support email.
3. I will give you the store text, screenshots and the privacy policy page to host on your existing hosting.

## Step 9. The web address: duebook.sparkingasia.com (15 minutes, free)

The app already uses this address for invite links, and Google needs a home page and a privacy policy on it before Google sign in can be published. The pages live in `docs/web/` in the repository; Cloudflare Pages serves them for free and redeploys on every push.

1. Go to dash.cloudflare.com and sign in or create a free account.
2. Left menu **Workers & Pages**, **Create**, **Pages** tab, **Connect to Git**. Authorise GitHub and pick the repository `jawadislam92/Khatabook`.
3. Project name `duebook`. Production branch: the branch I push to (currently `claude/khatabook-field-service-plan-7dg24c`; `main` once we merge). Framework preset **None**. Build command: leave empty. Build output directory: `docs/web`. Press **Save and Deploy**. After a minute the site is live at `duebook.pages.dev`.
4. Open the project, **Custom domains**, **Set up a custom domain**, enter `duebook.sparkingasia.com`.
   - If the DNS of sparkingasia.com is already on Cloudflare, it adds the record for you.
   - If not, it shows a CNAME to add wherever your DNS lives: name `duebook`, target `duebook.pages.dev`. Add it and come back; the status turns to **Active** within a few minutes.
5. Check `https://duebook.sparkingasia.com` and `https://duebook.sparkingasia.com/privacy` open on your phone.

Later the same address serves the Android app link file for invites and the public invoice link, with no further setup on your side.

## Step 10. Optional: Google sign in (15 minutes, free)

Email and password already work. This adds the **Continue with Google** button. The app opens the phone's browser, Google confirms the account, and Supabase hands the session back to the app through the link `com.sparkingasia.duebook://login-callback`. One Google client serves both Supabase projects.

**Part A. Google Cloud, once**

1. Go to console.cloud.google.com and pick the project Firebase made, **duebook-1acb5** (project picker at the top).
2. Left menu, **APIs and Services**, **OAuth consent screen** (Google now calls this page **Google Auth Platform**, **Branding**). App name `Duebook`, user support email and developer contact email: yours. Save.
3. Google will not let you press **Publish app** until the Branding page also has an application home page link and a privacy policy link on a domain you own. Two ready pages are in `docs/web/` (`index.html` and `privacy.html`). Step 9 puts them at `https://duebook.sparkingasia.com` and `https://duebook.sparkingasia.com/privacy`. Then on Branding press **Add domain** and enter `sparkingasia.com`, paste the two links, save, and on **Audience** press **Publish app**. User type stays **External**. Basic sign in only asks for name and email, so no Google review is needed.
   Until the pages are up, the app can stay in **Testing**: on Audience press **Add users** and type the Gmail addresses of the people who should sign in with Google (yours first). Everyone else can still use email and password.
4. **Credentials**, **Create credentials**, **OAuth client ID**. Application type **Web application** (yes, web, even though it is an Android app: the browser does the sign in). Name `Duebook Supabase`.
5. Under **Authorised redirect URIs** add both lines, exactly:
   - `https://jepcsftdjejjzhfjnavy.supabase.co/auth/v1/callback`
   - `https://ohrnkvzemgfrxcuknamh.supabase.co/auth/v1/callback`
6. Press **Create**. Copy the **Client ID** and the **Client secret**. Keep the window open, you need them twice.

**Part B. Supabase, on dev and again on prod**

7. Open the project, **Authentication**, **Sign In / Providers**, find **Google**, switch it on, paste the Client ID and Client secret, save.
8. Still under Authentication, open **URL Configuration**. Under **Redirect URLs** press **Add URL** and enter `com.sparkingasia.duebook://login-callback`. Save. Without this line Supabase sends the signed in user to the website address instead of back into the app, and the button appears to do nothing.
9. Repeat 7 and 8 on the other project.

**Part C. Try it**

10. In the app tap **Continue with Google**. The browser opens, you pick the account, and the app comes back signed in. The first time, Google shows a short consent page with the app name from step 2.

Nothing to send me. The client secret stays in Google and Supabase only.

---

## What happens on my side after each step

| After | I do |
|---|---|
| Step 1 | Rename the package, set the final name and colours |
| Step 2 | First deployment to the dev project, real sign in, CI goes green |
| Step 3 | Push notifications wired, confirm button in notifications |
| Step 4 | Nightly backup function and a restore drill |
| Step 5 | Invoice template with your branding and the real item catalog |
| Step 6 | First APK on the Play internal testing track |
| Step 7 | Signed release builds from tags |
| Step 10 | Check Google sign in on both projects from the app |
