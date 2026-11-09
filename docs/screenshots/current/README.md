# Screenshots

Taken from the web preview build at phone size (412 by 915, 2x). Preview mode uses in memory sample data.

| File | Screen |
|---|---|
| 01 to 03 | Onboarding: language, Urdu applied live, Big and Simple or Standard |
| 04 | Sign in, Big and Simple mode |
| 05, 06 | Set and confirm a PIN |
| 07 | Spaces list |
| 11 | Ledger home: will get and will give, the two big buttons, reminders, people |
| 12 | Add entry step 1: who is this with |
| 13 | Add entry step 2: amount keypad with the amount in words and quick amounts |
| 14 | Plain sentence confirmation before saving |
| 15 | Person page: balance, Gave and Got, WhatsApp reminder, statement, entry history |
| 16 | Entry detail with edit and cancel |

To retake: `flutter build web --release --no-tree-shake-icons --pwa-strategy=none`, serve `build/web` on port 8099, then `node app/tool_screenshots.js <out_dir> http://localhost:8099/ app/build/web/canvaskit`.
| 21 | Family group home with the who recorded what strip |
| 22 | Members and settings: invite, roles, month lock, leave |
| 23, 24 | Invite: choose a role, then the single use link to share |
| 26 | Join a group from a pasted link, with the preview before joining |
| 31 | Business Today board: today's jobs with status, late flag, who is on each, later jobs |
| 32, 33 | Job detail before and after the installer confirms |
| 34 | New job: customer, title, type, when, who goes |
| 35 | Item catalog by category, cost price visible to the owner only |
| 36 | Notification inbox |
| 40 | Job in progress: the installer has started work, the Finish job button is up |
| 41, 42 | Finish job: quick tiles for favourite items, search, other charge, then the lines with quantities and the running total |
| 43, 44, 44b | The bill: lines, discount, how much was paid now, the method chips once an amount is typed, balance due |
| 45 | Plain sentence confirmation before the bill is issued |
| 46 | The issued bill: totals, items, payments, Share PDF, WhatsApp, Record payment |
| 47 | Record a payment: amount, method, note |
| 48 | Bills tab: this month billed, received, jobs done, unpaid total, the unpaid list |
| 49 | Business details: what prints on every bill |
| 50 | Items used this month report |

Rendered PDF bills (English and Urdu) are in [../pdf](../pdf).
