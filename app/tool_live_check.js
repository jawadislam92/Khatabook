// Usage: node tool_live_check.js <out_dir> <base_url> <canvaskit_dir> <email> <password>
// Signs in to the real backend through the web build, creates a business space and a job,
// opens the job and prints every request the app makes along the way.
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
      .filter(x => x.r.width > 0 && x.r.height > 0 && x.r.top >= 0 && x.r.bottom <= window.innerHeight)
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
async function hasText(page, t) { return page.evaluate((t) => [...document.querySelectorAll('flt-semantics')].some(e => (e.textContent || '').includes(t)), t); }
async function typeInto(page, label, value) { if (await tapText(page, label)) { await page.keyboard.type(value, { delay: 15 }); await page.waitForTimeout(300); } }
async function texts(page) { return page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map(e => (e.getAttribute('aria-label') || e.textContent || '').trim()).filter(Boolean).filter((v, i, a) => a.indexOf(v) === i).slice(0, 40)); }

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 412, height: 915 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log(stamp(), 'PAGEERROR', e.message));
  page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') console.log(stamp(), 'console.' + m.type(), m.text().slice(0, 300)); });
  page.on('request', r => { const u = r.url(); if (u.includes('supabase.co')) console.log(stamp(), '->', r.method(), u.replace(/^https:\/\/[^/]+/, '').slice(0, 170)); });
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
  console.log('spaces screen texts:', JSON.stringify(await texts(page)));
  if (!(await hasText(page, 'QA Biz'))) {
    await tapText(page, 'New book');
    await typeInto(page, 'Book name', 'QA Biz');
    await tapText(page, 'Customers, jobs and bills.');
    await shot(page, '05-new-group-dialog');
    await tapText(page, 'Create');
    await page.waitForTimeout(3000);
  }
  await shot(page, '06-after-create');
  if (!(await hasText(page, 'New job'))) { await tapText(page, 'QA Biz'); await page.waitForTimeout(2500); }
  await shot(page, '07-business-home');
  console.log('business home texts:', JSON.stringify(await texts(page)));
  await tapText(page, 'New job');
  await page.waitForTimeout(1500);
  await shot(page, '08-new-job');
  console.log('new job texts:', JSON.stringify(await texts(page)));
  await typeInto(page, 'What needs doing', 'Test camera job');
  await tapText(page, 'Pick a customer');
  await page.waitForTimeout(800);
  console.log('picker texts:', JSON.stringify(await texts(page)));
  // Reuse the test customer once it exists, so every run does not add
  // another one (the app now asks before adding a second with the same name).
  if (!(await tapText(page, 'Test Customer', 3000))) {
    await tapText(page, 'New customer');
    await page.waitForTimeout(800);
    console.log('party form texts:', JSON.stringify(await texts(page)));
    await typeInto(page, 'Name', 'Test Customer');
    await tapText(page, 'Save');
    await page.waitForTimeout(1500);
  }
  await page.waitForTimeout(800);
  await tapText(page, 'QA One', 3000);
  await shot(page, '09-new-job-filled');
  console.log('=== saving the job (app then opens its detail) ===');
  await tapText(page, 'Save');
  await page.waitForTimeout(6000);
  await shot(page, '10-after-save-job');
  console.log('after save texts:', JSON.stringify(await texts(page)));
  console.log('=== back to the list, then tap the job like a user ===');
  await tapText(page, 'Back', 3000);
  await page.waitForTimeout(2500);
  await shot(page, '11-back-on-home');
  console.log('home texts:', JSON.stringify(await texts(page)));
  await tapText(page, 'Test camera job', 8000);
  await page.waitForTimeout(6000);
  await shot(page, '12-job-detail');
  console.log('job detail texts:', JSON.stringify(await texts(page)));
  await browser.close();
})().catch(e => { console.log('SCRIPT ERROR', e.message); process.exit(1); });
