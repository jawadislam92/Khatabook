# Product Plan

This document explains what we are building, for whom, how each part works, and in what order we build it. The technical side (stack, database, security) is in [TECHNICAL.md](TECHNICAL.md).

---

## 1. Who will use it

| Person | What they need | What they fear |
|---|---|---|
| Family members, many of them middle aged or elderly | Write down money given or taken. See at a glance who owes them and whom they owe. Get reminded when something is due. | Small text, too many screens, pressing the wrong thing, losing a record, strangers seeing their money matters. |
| The family as a group | A shared view: how much the family will get and how much the family has to give, and who recorded what. | Someone changing or deleting an entry quietly. |
| Uncle (business owner) | Take a call, book a job for 10 am, and know for sure the team knows about it. See today's jobs and their status. Get an invoice the moment the job is done. Track who still owes him. | Forgetting to tell the team. Not knowing what materials were used. Customers who "will pay later". |
| Installers and technicians | See their jobs for today with address and phone. Confirm they have seen it. Update status with one tap. Record what they used. Hand the customer an invoice before leaving. | Fiddly forms on a small phone in the sun, no signal at the site. |
| Customers | A clear invoice on WhatsApp. | Nothing to install. They never need the app. |

---

## 2. Product principles

1. **One screen, one job.** Each screen asks for one thing. No screen needs explanation.
2. **Big and readable.** Simple mode makes text and buttons larger and cuts the choices down to what matters.
3. **Two languages.** English and Urdu, switchable per person. Roman Urdu as a third option if wanted.
4. **Nothing is silently lost.** Entries are never hard deleted. Every change records who did it and when. Undo instead of "Are you sure?".
5. **Works with poor signal.** Entries and job updates save on the phone first and sync when the network returns.
6. **Private by default.** A ledger is only visible to the people invited to it. Business cost prices stay hidden from the team unless the owner says otherwise.

---

## 3. How the app is organised

After login the person lands on **Spaces**. A space is a container with its own members and ledgers.

- **Personal**: only you. Created automatically.
- **Family** (a group): members, shared ledgers, group dashboard, activity feed.
- **Business** (a group with business features turned on): everything a group has, plus customers, jobs, item catalog, invoices, reports.

Why one app instead of two: same login, same ledger engine, and the uncle's installers may also be family members. Business features are simply a switch on a group, so we do not build or maintain two apps.

Bottom tabs change per space:

| Space | Tabs |
|---|---|
| Personal / Family | Home, Parties, Activity, More |
| Business (owner) | Today, Jobs, Customers, Ledger, More |
| Business (installer) | My Jobs, Customers (limited), More |

---

## 4. Features

### 4.1 Ledger (the core, shared by every space)

- **Parties**: people or shops you deal with. Name, phone, photo, optional link to an app user. Import from phone contacts with permission.
- **Entries**: "I gave" or "I got", amount, date, note, photo of a receipt or bill. Records who added it.
- **Balances**: running balance per party, totals per ledger book. Colour, arrow icon, and words together, so colour blindness or a dim screen does not cause mistakes. "You will get Rs 5,000" in green with an arrow in. "You will give Rs 2,000" in red with an arrow out.
- **Reminders**: set a due date on a party balance. The app reminds you. One tap opens WhatsApp or SMS with a ready message in the chosen language: "Salam Bilal bhai, aap ki taraf Rs 5,000 baqaya hain. Shukriya."
- **Statements**: PDF statement per party or per book, with a date range, share or print.
- **Multiple books** per space: "Home", "Committee", "Shop", "Wedding".
- **Edit history**: every entry shows its changes. Deleting creates a reversal and the original stays visible as struck through.
- **Search and filter** by party, date, amount, who added it.
- **Month lock** (owner only): freeze a month so nothing in it can change.

### 4.2 Family and team groups

- **Create a group and invite** by a link or by phone number. Invite links expire in 48 hours and work once.
- **Roles**:
  - Owner: everything, including deleting the group and locking months.
  - Manager: add and edit entries, manage parties and members.
  - Member: add entries, see everything.
  - Viewer: see only.
- **Group dashboard**: total the family will get, total the family has to give, net position. Breakdown by party and by who recorded it.
- **Activity feed**: "Ammi added Rs 5,000 got from Bilal, 2 hours ago". Taps through to the entry.
- **Notifications**: a new entry in a shared book (can be turned off per book), a reminder due, a member joined.
- **Later**: settle up between members (who paid for a family expense and who owes them a share).

### 4.3 Business: customers and jobs

This is the fix for "he booked 10 am and forgot to tell the installers".

- **Customers**: same as parties, plus address, map pin, site photos, notes like "DVR is in the store room".
- **Job**: title ("2 cameras not recording"), customer, address, date and time, assigned team members, job type (CCTV install, CCTV repair, Solar install, Solar service, Other), notes, optional estimated price. Created by the owner or manager in under a minute: pick customer, pick time, pick people, done.
- **Job statuses**: Scheduled, Confirmed (someone on the team acknowledged), On the way, Working, Finished, Invoiced, Paid. Also Cancelled and Rescheduled.
- **Notification rules**:

  | When | Who gets it | What |
  |---|---|---|
  | Job created or someone assigned | Each assigned installer | "New job: Mr Ahmed, F-10, tomorrow 10 am. Tap to confirm." with a Confirm button right in the notification |
  | 30 minutes after creation, nobody confirmed | Installers again, and the owner | Owner sees "Nobody has confirmed the 10 am job for Mr Ahmed" |
  | Evening before, 8 pm | Owner and the whole team | Tomorrow's jobs list |
  | 1 hour before start | Assigned installers | Reminder with address and call button |
  | Status changes | Owner | "Bilal is on the way to Mr Ahmed" / "Job finished, invoice ready" |
  | Rescheduled or cancelled | Everyone on the job | New time or cancellation |

- **Today board** (owner): a timeline of today's jobs, colour by status, who is on each, late jobs flagged.
- **My Jobs** (installer): today's jobs as big cards. Buttons: Confirm, On the way, Start, Finish. Call customer, open in Google Maps. Add photos before and after.
- **Job history** per customer: every visit, what was done, what was used, what was charged.

### 4.4 Invoice on the spot

- **Item catalog**, maintained by the owner: name in English and Urdu, unit (piece, meter, set, hour), default sale price, optional cost price (hidden from installers), category (Camera, DVR/NVR, Cable, Connectors and accessories, Solar panel, Inverter, Battery, Structure, Wiring, Labour, Visit charge). Mark favourites so they show as quick tiles.
- **Finish job flow** (installer):
  1. Tap Finish.
  2. Pick items used: quick tiles for common items, search for the rest, set quantity with big plus and minus buttons.
  3. Add labour or service charge (prefilled from catalog, editable if the owner allows).
  4. Optional discount and note (warranty, next service date).
  5. Take a photo of the finished work.
  6. Preview invoice. Tap Share. WhatsApp opens on the customer's number with the PDF attached.
- **Invoice contents**: business name, logo, phone, address; invoice number (INV-2026-0001); customer name and phone; date; line items with quantity, rate, amount; subtotal; discount; tax line if enabled; total; amount received now; balance due; warranty or terms text; payment details (bank, EasyPaisa, JazzCash).
- **Approval setting**: either the invoice goes out as soon as the installer shares it, or it waits for the owner to approve (owner gets a notification and a one tap Approve). Owner chooses.
- **Payments**: record cash, bank transfer, EasyPaisa, JazzCash, with date and note. Partial payments allowed.
- **Automatic udhaar**: any balance due on an invoice becomes an entry against the customer in the business ledger. When a payment is recorded, the ledger updates. So the owner's khatabook and his invoices never disagree.
- **Share again** any time from the job or the customer page. Invoice also available as a link that expires after 30 days.
- **Reports** (owner): jobs this week and month, revenue, unpaid invoices and ageing, items used (what to restock), jobs per installer.

### 4.5 Settings, simple mode, accessibility

- **Simple mode** (offered at first launch as "Who will use this phone? Choose Big and Simple", and switchable any time):
  - text 130 percent, buttons at least 56 dp tall, high contrast, bold labels
  - home shows two big numbers (will get, will give) and two big buttons ("I gave money", "I got money")
  - amounts also shown in words: "Rs 5,000 (paanch hazaar)"
  - plain sentence confirmation before saving: "You gave Rs 5,000 to Bilal today. Correct?"
  - no swipe gestures needed, visible back button on every screen, no hidden menus
  - fewer options on each screen; advanced things move under "More"
- **Language**: English, Urdu (right to left layout), Roman Urdu. Per person, changeable any time.
- **App lock**: PIN, fingerprint or face. Optional auto lock after one minute in the background.
- **Backup and export**: CSV and PDF export of any book at any time. Data lives in the cloud, so a lost phone does not mean lost records.
- **Dark mode** follows the phone setting.
- **Screen reader support** (TalkBack) with proper labels on every control.

---

## 5. Key screens

Personal and Family
1. Spaces list
2. Home (balances, big buttons)
3. Party list with search
4. Party page (balance, entries, remind, statement)
5. Add entry (amount pad, gave or got, date, note, photo)
6. Entry detail with history
7. Group dashboard
8. Activity feed
9. Members and invites
10. Settings (simple mode, language, lock, export)

Business
11. Today board
12. Jobs list with filters
13. New job
14. Job detail (status, team, customer, photos, invoice)
15. My Jobs (installer)
16. Finish job: items used
17. Invoice preview and share
18. Customers and customer page with job history
19. Item catalog
20. Payments and unpaid invoices
21. Reports

---

## 6. Flows in plain words

**A. Ammi records money.** Opens app, fingerprint, sees Home with "Will get Rs 12,000" and "Will give Rs 3,500". Taps "I got money". Picks Bilal from the list (recent names first). Types 5000 on a big keypad. Sees "You got Rs 5,000 from Bilal today. Correct?" Taps Yes. Done in four taps. Family members with notifications on see "Ammi added Rs 5,000 got from Bilal".

**B. Family checks where things stand.** Any member opens Family space. Dashboard says the family will get Rs 48,000 in total and has to give Rs 15,000. Tapping a number shows the parties behind it. Tapping a party shows every entry and who recorded it.

**C. Uncle books a job.** Customer calls. Uncle opens Business, taps New Job. Picks the customer (or types a new name and phone). Picks "Tomorrow 10 am". Picks Bilal and Saeed. Types "2 cameras not recording". Saves. Both installers get a push notification immediately with a Confirm button. Bilal confirms. Uncle sees the job turn green on his Today board for tomorrow. At 8 pm everyone gets tomorrow's list. At 9 am Bilal and Saeed get a reminder with the address.

**D. Installer finishes and invoices.** Saeed taps On the way, then Start on arrival. After the work, taps Finish. Picks "Dome camera 2 MP x 2", "Cable 20 m", "Service charge". Adds a 500 rupee discount. Takes a photo. Previews the invoice, Rs 9,500 total. Customer pays Rs 5,000 cash now; Saeed records it. Taps Share, WhatsApp opens, PDF goes to the customer. Uncle gets "Job finished, invoice INV-2026-0042, Rs 4,500 due". The customer now shows Rs 4,500 balance in the business ledger.

**E. Customer pays later.** Two weeks later the customer sends Rs 4,500 by EasyPaisa. Uncle opens the customer, taps Record payment, EasyPaisa, Rs 4,500. Invoice becomes Paid. Ledger balance becomes zero. If the customer had not paid, the reminder feature nudges uncle and gives him a one tap WhatsApp message with the balance.

---

## 7. Build phases

Each phase ends with a working build on real phones. Times are rough and assume steady work.

| Phase | What ships | Rough time |
|---|---|---|
| 0. Foundation | Decisions below settled. Supabase project, repo structure, CI that builds an APK, design tokens, English and Urdu string files, login, app lock, simple mode framework. | 1 week |
| 1. Personal ledger | Parties, entries, balances, entry history and reversal, reminders, PDF statement, search, export. Installable on family phones. | 2 to 3 weeks |
| 2. Family groups | Groups, invites, roles, shared books, group dashboard, activity feed, push notifications for shared entries, month lock. | 2 weeks |
| 3. Jobs and team notifications | Business toggle, customers, item catalog, jobs, assignment, statuses, the full notification rule set, Today board, My Jobs. | 2 to 3 weeks |
| 4. Invoicing | Finish job flow, invoice PDF, numbering, share via WhatsApp and link, payments, automatic ledger entries, approval setting, reports. | 2 weeks |
| 5. Hardening and release | Offline queue, security review against the checklist in TECHNICAL.md, backups, Play Store internal testing then production, help screens, onboarding. iOS build if wanted. | 2 weeks |

Phases 1 and 2 give the family a usable app early while the business part is built.

---

## 8. Not in version one

- Stock levels and inventory counts (the catalog records what was used, not what is in the store)
- Accounting, tax filing, double entry books
- A customer facing app or portal
- Online payment collection inside the app
- Multiple currencies
- Bluetooth receipt printer (can be added, there are libraries for it)
- iOS release before Android is stable

---

## 9. Decisions needed before coding

Please answer what you can. Where you do not have a view, the recommendation in bold is what we will go with.

1. **Login method.** Phone number with SMS code is the most natural for elders, but every SMS costs money and delivery in Pakistan can be slow. **Recommendation: email or Google sign in for setup, then fingerprint or PIN for daily use.** Phone number is still recorded on the profile for contact matching. We can add SMS login later if needed.
2. **Languages.** English and Urdu for sure. Do you also want Roman Urdu? **Recommendation: English and Urdu first, Roman Urdu in phase 5.**
3. **Platforms.** **Recommendation: Android first.** Does anyone in the family or team use an iPhone? If yes we plan the iOS build and the Apple developer account (USD 99 a year).
4. **Business name, logo, address, and payment details** for the invoice header. Also the exact job types and the first version of the item catalog (names, units, prices). A photo of an existing handwritten bill helps.
5. **Can installers change prices** on the invoice, or only quantities? **Recommendation: quantities only, prices locked, with a per item "allow price edit" switch for things like labour.**
6. **Invoice approval.** Should invoices go to the customer as soon as the installer shares, or wait for uncle's approval? **Recommendation: go immediately, uncle gets notified, can issue a corrected invoice.**
7. **Tax on invoices.** Does the business charge sales tax on invoices? **Recommendation: a tax line that is off by default.**
8. **Who can see profit.** Cost prices and reports visible to owner only, or also to a manager?
9. **Team size and family size** roughly, so we size the plan. Free tiers cover a few hundred people comfortably.
10. **Family dashboard scope.** Should the family dashboard combine every member's personal ledger, or only the shared family books? **Recommendation: only shared books. Personal stays personal unless a member chooses to share a book.**
11. **Reminder messages.** Any preferred wording for the WhatsApp reminder templates in Urdu and English?
12. **Name of the app** and a colour you like, for the icon and theme.
