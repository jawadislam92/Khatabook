// Usage: node tool_features_check.js <out_dir> <base_url> <canvaskit_dir> <email> <password>
// Checks the 11 November changes on the real web build against dev: no
// Personal book, the new book box offers Family or Business, switches, and
// importing people from a contacts file into the Family book.
// Prints PASS or FAIL per check and exits 1 if any check failed.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const [out, base, ckDir, email, password] = process.argv.slice(2);
const t0 = Date.now();
const stamp = () => ((Date.now() - t0) / 1000).toFixed(1).padStart(6) + 's';

async function shot(page, name) { await page.waitForTimeout(700); await page.screenshot({ path: path.join(out, name + '.png') }); console.log(stamp(), 'shot', name); }
async function enableSemantics(page) {
  await page.evaluate(() => { const el = document.querySelector('flt-semantics-placeholder[role="button"]'); if (el) el.dispatchEvent(new MouseEvent('click', { bubbles: true })); });
  await page.waitForTimeout(1200);
}
async function findText(page, text) {
  return page.evaluate((t) => {
    const els = [...document.querySelectorAll('flt-semantics, input, textarea')]
      .filter(e => (e.textContent || '').includes(t) || (e.getAttribute('aria-label') || '').includes(t))
      .map(e => ({ r: e.getBoundingClientRect(), pri: (e.getAttribute('role') === 'button' || e.tagName === 'INPUT') ? 0 : 1 }))
      .filter(x => x.r.width > 0 && x.r.height > 0)
      .sort((a, b) => a.pri - b.pri || a.r.width * a.r.height - b.r.width * b.r.height).map(x => x.r);
    return els.length ? { x: els[0].x + els[0].width / 2, y: els[0].y + els[0].height / 2 } : null;
  }, text);
}
async function tapText(page, text, timeout = 15000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const box = await findText(page, text);
    if (box) { await page.mouse.click(box.x, box.y); await page.waitForTimeout(700); console.log(stamp(), 'tap', text); return true; }
    await page.waitForTimeout(300);
  }
  console.log(stamp(), 'NOT FOUND', text); return false;
}
async function hasText(page, t) { return page.evaluate((t) => [...document.querySelectorAll('flt-semantics')].some(e => (e.textContent || '').includes(t) || (e.getAttribute('aria-label') || '').includes(t)), t); }
async function typeInto(page, label, value) { if (await tapText(page, label)) { await page.keyboard.type(value, { delay: 15 }); await page.waitForTimeout(300); } }
async function texts(page) { return page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map(e => (e.getAttribute('aria-label') || e.textContent || '').trim()).filter(Boolean).filter((v, i, a) => a.indexOf(v) === i).slice(0, 40)); }

let failed = 0;
const check = (ok, label) => { console.log(stamp(), ok ? "PASS" : "FAIL", label); if (!ok) failed++; };

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 412, height: 915 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log(stamp(), 'PAGEERROR', e.message));
  page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') console.log(stamp(), 'console.' + m.type(), m.text().slice(0, 300)); });
  
  page.on('response', async r => { const u = r.url(); if (u.includes('supabase.co') && r.status() >= 400) { let b = ''; try { b = (await r.text()).slice(0, 300); } catch (_) {} console.log(stamp(), '<-', r.status(), u.replace(/^https:\/\/[^/]+/, '').slice(0, 120), b); } });
  page.on('requestfailed', r => { const u = r.url(); if (u.includes('supabase.co')) console.log(stamp(), 'FAILED', r.method(), u.slice(0, 160), r.failure() && r.failure().errorText); });
  await page.route('https://www.gstatic.com/flutter-canvaskit/**', route => {
    const u = new URL(route.request().url()); const rel = u.pathname.split('/').slice(3).join('/'); const file = path.join(ckDir, rel);
    const type = file.endsWith('.js') ? 'application/javascript' : file.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream';
    route.fulfill({ status: 200, contentType: type, body: fs.readFileSync(file) });
  });
  await page.goto(base, { waitUntil: 'networkidle' });
  await page.waitForTimeout(4000);
  await enableSemantics(page);
  await shot(page, '01-start');
  if (await hasText(page, 'English')) { await tapText(page, 'English'); await tapText(page, 'Continue'); }
  if (await hasText(page, 'Standard')) { await tapText(page, 'Standard'); await tapText(page, 'Continue'); }
  await shot(page, '02-auth');
  await typeInto(page, 'Email', email);
  await typeInto(page, 'Password', password);
  await tapText(page, 'Sign in');
  await page.waitForTimeout(4000);
  await shot(page, '03-after-sign-in');
  if (!(await hasText(page, 'New book')) && (await findText(page, '1'))) {
    for (const d of ['1', '2', '5', '8']) await tapText(page, d, 3000);
    await tapText(page, 'Continue', 3000);
    for (const d of ['1', '2', '5', '8']) await tapText(page, d, 3000);
    await tapText(page, 'Continue', 3000);
    await page.waitForTimeout(2000);
  }
  await shot(page, '04-spaces');
  check(!(await hasText(page, 'Personal')), 'no Personal book on the books list');
  check(await hasText(page, 'Family'), 'a Family book is on the books list');

  await tapText(page, 'New book');
  await page.waitForTimeout(800);
  check(await hasText(page, 'What is this book for?'), 'new book box asks what the book is for');
  check(await hasText(page, 'Money you spend, give and get'), 'new book box offers Family');
  check(await hasText(page, 'Customers, jobs and bills.'), 'new book box offers Business');
  await shot(page, 'f1-new-book');
  await tapText(page, 'Cancel');
  await page.waitForTimeout(800);

  await tapText(page, 'Settings');
  await page.waitForTimeout(1500);
  await shot(page, 'f2-settings-switches');
  await page.goBack(); await page.waitForTimeout(1500);

  // The Family book: the menu has Import contacts, which takes a file here.
  await tapText(page, 'Family');
  await page.waitForTimeout(2500);
  await tapText(page, 'Show menu');
  check(await tapText(page, 'Import contacts'), 'book menu has Import contacts');
  await page.waitForTimeout(1500);
  check(await hasText(page, 'Choose contacts file'), 'on the web it asks for a contacts file');
  const vcf = path.join(out, 'sample.vcf');
  fs.writeFileSync(vcf, 'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Web Test Zubair\r\nTEL;TYPE=CELL:0300 5550001\r\nEND:VCARD\r\nBEGIN:VCARD\r\nVERSION:3.0\r\nFN:Web Test Ayesha\r\nTEL;TYPE=CELL:0321 5550002\r\nEND:VCARD\r\n');
  const [chooser] = await Promise.all([page.waitForEvent('filechooser', { timeout: 15000 }), tapText(page, 'Choose contacts file')]);
  await chooser.setFiles(vcf);
  await page.waitForTimeout(2500);
  await shot(page, 'f3-import-list');
  check(await hasText(page, 'Web Test Zubair') && await hasText(page, 'Web Test Ayesha'), 'contacts from the file are listed');
  const already = await hasText(page, 'Already in this book');
  if (!already) {
    await tapText(page, 'Select all');
    check(await hasText(page, 'Add 2 people'), 'select all picks both');
    await tapText(page, 'Add 2 people');
    await page.waitForTimeout(4000);
  }
  await shot(page, 'f4-after-import');
  if (await hasText(page, 'Choose contacts file')) { await tapText(page, 'Back', 5000); await page.waitForTimeout(2000); }
  check(await hasText(page, 'Web Test Zubair'), already ? 'people from an earlier run show as already in the book' : 'imported people are in the book');

  // Add person: the contacts file chosen above gives suggestions while typing.
  await tapText(page, 'New person');
  await page.waitForTimeout(1000);
  check(await hasText(page, 'Pick from contacts'), 'Add person has Pick from contacts');
  await shot(page, 'f5-add-person');

  await browser.close();
  console.log(failed ? `${failed} check(s) FAILED` : 'ALL CHECKS PASSED');
  process.exit(failed ? 1 : 0);
})();
