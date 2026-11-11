// Usage: node tool_offline_check.js <out_dir> <base_url> <canvaskit_dir> <email> <password>
// Signs in to the real backend through the web build, then breaks the job
// requests two ways and checks the app shows the error with a retry button:
//   1. the requests fail at once (like a phone with no signal),
//   2. the requests hang with no answer (like a dropped Wi-Fi link),
//      which must end in the error within the app's 30 second limit.
// After each case the network comes back and "Try again" must load the job.
// Prints PASS or FAIL per check and exits 1 if any check failed.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const [out, base, ckDir, email, password] = process.argv.slice(2);
const t0 = Date.now();
const stamp = () => ((Date.now() - t0) / 1000).toFixed(1).padStart(6) + 's';
let failed = 0;
const check = (ok, label) => { console.log(stamp(), ok ? 'PASS' : 'FAIL', label); if (!ok) failed++; };

async function shot(page, name) { await page.waitForTimeout(500); await page.screenshot({ path: path.join(out, name + '.png') }); console.log(stamp(), 'shot', name); }
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
// Taps the n-th (from 0, top to bottom) visible element showing the text.
async function tapNth(page, text, n) {
  const box = await page.evaluate(([t, n]) => {
    const rs = [...document.querySelectorAll('flt-semantics')]
      .filter(e => (e.textContent || '').includes(t) && ![...e.children].some(c => (c.textContent || '').includes(t)))
      .map(e => e.getBoundingClientRect()).filter(r => r.width > 0 && r.height > 0)
      .sort((a, b) => a.y - b.y);
    const r = rs[n];
    return r ? { x: r.x + r.width / 2, y: r.y + r.height / 2 } : null;
  }, [text, n]);
  if (box) { await page.mouse.click(box.x, box.y); await page.waitForTimeout(700); console.log(stamp(), 'tap', text, '#' + n); return true; }
  console.log(stamp(), 'NOT FOUND', text, '#' + n); return false;
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
async function waitText(page, t, ms) { const end = Date.now() + ms; while (Date.now() < end) { if (await hasText(page, t)) return true; await page.waitForTimeout(500); } return false; }
async function typeInto(page, label, value) { if (await tapText(page, label)) { await page.keyboard.type(value, { delay: 15 }); await page.waitForTimeout(300); } }

const ERROR = 'Something went wrong';
const RETRY = 'Try again';
const JOB_READS = /\/rest\/v1\/(jobs|job_events|job_items)\?/;

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 412, height: 915 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log(stamp(), 'PAGEERROR', e.message));
  page.on('console', m => { if (m.text().includes('error report')) console.log(stamp(), 'CONSOLE', m.text().slice(0, 200)); });
  page.on('response', async r => { const u = r.url(); if (u.includes('supabase.co') && r.status() >= 400) { let b = ''; try { b = (await r.text()).slice(0, 200); } catch (_) {} console.log(stamp(), '<-', r.status(), u.replace(/^https:\/\/[^/]+/, '').slice(0, 110), b); } });
  page.on('request', r => { if (r.url().includes('/rest/v1/client_errors')) console.log(stamp(), 'error report sent'); });
  await page.route('https://www.gstatic.com/flutter-canvaskit/**', route => {
    const u = new URL(route.request().url()); const rel = u.pathname.split('/').slice(3).join('/'); const file = path.join(ckDir, rel);
    const type = file.endsWith('.js') ? 'application/javascript' : file.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream';
    route.fulfill({ status: 200, contentType: type, body: fs.readFileSync(file) });
  });

  await page.goto(base, { waitUntil: 'networkidle' });
  await page.waitForTimeout(4000);
  await enableSemantics(page);
  if (await hasText(page, 'English')) { await tapText(page, 'English'); await tapText(page, 'Continue'); }
  if (await hasText(page, 'Standard')) { await tapText(page, 'Standard'); await tapText(page, 'Continue'); }
  await typeInto(page, 'Email', email);
  await typeInto(page, 'Password', password);
  await tapText(page, 'Sign in');
  await page.waitForTimeout(4000);
  if (!(await hasText(page, 'New book')) && (await findText(page, '1'))) {
    for (let round = 0; round < 2; round++) { for (const d of ['1', '2', '5', '8']) await tapText(page, d, 3000); await tapText(page, 'Continue', 3000); }
    await page.waitForTimeout(2000);
  }
  check(await waitText(page, 'QA Biz', 15000), 'signed in and the spaces list loaded');
  await tapText(page, 'QA Biz');
  check(await waitText(page, 'Test camera job', 15000), 'business home shows the test job');
  await shot(page, 'o1-business-home');

  // Case 1: requests fail at once.
  let mode = 'fail';
  await page.route(JOB_READS, async route => {
    if (route.request().method() !== 'GET') return route.continue();
    if (mode === 'fail') return route.abort('internetdisconnected');
    if (mode === 'hang') { console.log(stamp(), 'held with no answer:', route.request().url().replace(/^https:\/\/[^/]+/, '').slice(0, 70)); return; } // never answer
    return route.continue();
  });
  // Each case opens a different job, because a job the app has already
  // loaded is shown from memory and needs no request.
  await tapNth(page, 'Test camera job', 0);
  const quick = await waitText(page, ERROR, 15000);
  await shot(page, 'o2-no-signal');
  check(quick, 'no signal: the job screen shows the error instead of a spinner');
  check(await hasText(page, RETRY), 'no signal: a "Try again" button is there');
  mode = 'ok';
  await tapText(page, RETRY);
  check(await waitText(page, 'Who goes', 15000), 'no signal: "Try again" loads the job once the network is back');
  await shot(page, 'o3-after-retry');
  await tapText(page, 'Back', 5000);
  await page.waitForTimeout(2000);

  // Case 2: requests hang with no answer.
  mode = 'hang';
  const started = Date.now();
  // A different job card from case 1: the second one on the screen.
  await tapNth(page, 'Test camera job', 1);
  const hung = await waitText(page, ERROR, 40000);
  if (!hung) console.log(stamp(), 'still no error; waiting longer to see when it comes', (await waitText(page, ERROR, 60000)) ? 'came at ' + ((Date.now() - started) / 1000).toFixed(0) + 's' : 'never came');
  const secs = ((Date.now() - started) / 1000).toFixed(0);
  await shot(page, 'o4-no-answer');
  check(hung, `no answer: the error appears after ${secs}s (limit is 30s)`);
  mode = 'ok';
  await tapText(page, RETRY);
  check(await waitText(page, 'Who goes', 15000), 'no answer: "Try again" loads the job once the network is back');
  await shot(page, 'o5-after-retry');

  await page.waitForTimeout(3000); // let error reports leave the browser
  await browser.close();
  console.log(failed ? `${failed} check(s) FAILED` : 'ALL CHECKS PASSED');
  process.exit(failed ? 1 : 0);
})().catch(e => { console.log('SCRIPT ERROR', e.message); process.exit(1); });
