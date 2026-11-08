# Phase 0 screenshots

Taken from the web preview build at phone size (412 by 915, 2x). Preview mode uses in memory data and shows a banner saying so.

| File | Screen |
|---|---|
| 01-onboarding-language.png | First launch, language choice |
| 02-onboarding-language-urdu.png | Same screen after tapping Urdu: layout flips right to left immediately |
| 03-onboarding-mode.png | "Who will use this phone?" Big and Simple or Standard |
| 04-sign-in-simple.png | Sign in, Big and Simple mode (larger text, 56 dp buttons, black text) |
| 05-set-pin.png | Set a PIN with the on screen keypad |
| 06-confirm-pin.png | Confirm the PIN |
| 07-spaces-simple.png | Spaces list in Big and Simple mode |
| 08-settings.png | Settings: display, security, account |
| 09-settings-urdu-standard.png | Settings after switching to Urdu and Standard mode |
| 10-spaces-urdu.png | Spaces list in Urdu |

To retake them: build the web preview with `flutter build web --release --no-tree-shake-icons --pwa-strategy=none`, serve `build/web` on port 8099, then run `node app/tool_screenshots.js <out_dir> http://localhost:8099/ app/build/web/canvaskit`.
