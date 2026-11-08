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
