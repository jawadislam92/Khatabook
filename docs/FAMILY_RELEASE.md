# Giving Duebook to family and friends

Everything here is free. Do the parts in order. Each line is one click or one thing to type.

## Part 1. Supabase settings (about 5 minutes)

Do this on the live project first, then repeat on the test project.

1. Open https://supabase.com/dashboard and sign in.
2. Click the project **khatabook-prod**.
3. In the left menu click **Authentication**.
4. Click **Sign In / Providers**.
5. Turn on **Allow anonymous sign-ins**. This is what lets family join with only their name.
6. Turn on **Allow manual linking**. This lets them connect Google later so the login is not lost with the phone.
7. Click **Save changes**.
8. In the list of providers, click **Email**.
9. Set **Minimum password length** to `6`.
10. Set **Password requirements** to **No required characters**.
11. Click **Save**.
12. Go back to the project list and do steps 2 to 11 again for the test project (ref `jepcsftdjejjzhfjnavy`).

Optional: on the same Email page you can turn off **Confirm email**. Then people who sign up with an email can start at once instead of clicking a link in an email first. Anyone could then sign up with an email address that is not theirs. For a family app that is usually fine.

## Part 2. Google one tap (about 5 minutes)

1. Open https://console.cloud.google.com and sign in.
2. At the top, pick the project **Duebook**.
3. In the left menu click **APIs & Services**, then **Credentials**.
4. Click **Create credentials**, then **OAuth client ID**.
5. For **Application type** pick **Android**.
6. Name: `Duebook Android`.
7. Package name: `com.sparkingasia.duebook`
8. SHA-1 certificate fingerprint: `A0:3F:72:FA:0E:35:74:4B:40:BA:BB:55:E8:01:C3:16:DF:22:A5:21`
9. Click **Create**.
10. In the left menu click **Google Auth Platform** (or **OAuth consent screen**), then **Branding**.
11. App name: `Duebook`. Home page: `https://duebook.sparkingasia.com`. Privacy policy: `https://duebook.sparkingasia.com/privacy.html`.
12. Under **Authorised domains** add `sparkingasia.com`.
13. Click **Save**.
14. Click **Audience**, then **Publish app**, then **Confirm**.

Until step 14 is done, Google sign in only works for the test users listed on the Audience page.

## Part 3. Website files for invite links (about 5 minutes)

These make an invite link open the app. Without them the link opens a page in the browser that tells the person what to do.

1. Open Hostinger, then **File Manager** for sparkingasia.com.
2. Open the folder `public_html/duebook`.
3. Upload `docs/web/join.html` from this project.
4. Upload `docs/web/index.html` (the home page text now says Family book).
5. Create a folder named `.well-known` (with the dot) and upload `docs/web/.well-known/assetlinks.json` into it.
6. Upload `docs/web/.htaccess`. If a file named `.htaccess` is already there, open it and paste the lines from ours at the end instead.
7. Check it: open https://duebook.sparkingasia.com/.well-known/assetlinks.json in a browser. You should see some text with `com.sparkingasia.duebook`.

## Part 4. Keep the signing key safe

The folder `C:\src\duebook-keys` holds the key that signs the app, and its password. Every future update must be signed with this same key, or phones will refuse to install it over the old one.

1. Copy the whole folder `C:\src\duebook-keys` to a USB stick or to your private Google Drive.
2. Never send it to anyone, and never put it in the GitHub repository.

## Part 5. Send the app

The file is `C:\laragon\www\Duebook\duebook-prod.apk` (about 70 MB). It uses the live server.

1. Send the file on WhatsApp (as a Document) or share it from Google Drive.
2. The person taps the file, then **Install**.
3. If the phone says it cannot install from this source, they tap **Settings**, turn on **Allow from this source**, go back and tap **Install**.
4. If the phone already has an older test version of Duebook, uninstall that first (this is likely only your own phone).

## Part 6. Invite someone to your book

1. Open Duebook and open the **Family** book.
2. Tap the **Members** button at the top.
3. Tap **Invite someone**, pick **Member**, tap **Invite**.
4. Tap **Share link** and send it on WhatsApp.
5. They open Duebook, tap **Were you sent an invite link?**, paste the link, type their name, and tap **Join with my name**.

Each link works once and stops working after 48 hours. Make one link per person.

## Updates later

When there is a new version, send the new `duebook-prod.apk` the same way. It installs over the old one and keeps everything.

## iPhone

An iPhone version needs a Mac and a paid Apple developer account, so it is not part of this free setup.
