// Usage: node tool_screenshots.js <out_dir> <base_url> <path_to_build/web/canvaskit>
// Needs the web preview served at base_url. See docs/screenshots/phase0/README.md.
// Drives the web preview through the real screens and takes phone sized screenshots.
const { chromium } = require('playwright');
const path = require('path');
const out = process.argv[2];
const base = process.argv[3] || 'http://localhost:8099/';

async function shot(page, name) {
  await page.waitForTimeout(700);
  await page.screenshot({ path: path.join(out, name + '.png') });
  console.log('shot', name);
}
// Flutter web renders to canvas; semantics tree gives us clickable nodes.
async function enableSemantics(page) {
  // The placeholder sits off screen; dispatch the click directly instead of scrolling to it.
  await page.evaluate(() => {
    const el = document.querySelector('flt-semantics-placeholder[role="button"]');
    if (el) el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
  await page.waitForTimeout(1200);
}
// Find the smallest semantics node whose text starts with the label and click its centre
// with a real pointer event, so Flutter handles it like a finger tap.
async function tapText(page, text) {
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    const box = await page.evaluate((t) => {
      const els = [...document.querySelectorAll('flt-semantics, input, textarea')]
        .filter(e => (e.textContent || '').trim().startsWith(t) || (e.getAttribute('aria-label') || '').startsWith(t))
        .map(e => ({ r: e.getBoundingClientRect(), pri: (e.getAttribute('role') === 'button' || e.tagName === 'INPUT') ? 0 : 1 }))
        .filter(x => x.r.width > 0 && x.r.height > 0)
        .sort((a, b) => a.pri - b.pri || a.r.width * a.r.height - b.r.width * b.r.height)
        .map(x => x.r);
      return els.length ? { x: els[0].x + els[0].width / 2, y: els[0].y + els[0].height / 2 } : null;
    }, text);
    if (box) {
      await page.mouse.click(box.x, box.y);
      await page.waitForTimeout(700);
      return;
    }
    await page.waitForTimeout(300);
  }
  throw new Error('not found: ' + text);
}
async function typeInto(page, label, value) {
  await tapText(page, label);
  await page.keyboard.type(value, { delay: 20 });
  await page.waitForTimeout(300);
}

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 412, height: 915 }, deviceScaleFactor: 2 });
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log('pageerror', e.message));
  // The CanvasKit CDN is not reachable from here; serve the copy from the build instead.
  const fs = require('fs');
  const ckDir = process.argv[4];
  await page.route('https://www.gstatic.com/flutter-canvaskit/**', route => {
    const u = new URL(route.request().url());
    const rel = u.pathname.split('/').slice(3).join('/');
    const file = path.join(ckDir, rel);
    const type = file.endsWith('.js') ? 'application/javascript' : file.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream';
    route.fulfill({ status: 200, contentType: type, body: fs.readFileSync(file) });
  });
  await page.goto(base, { waitUntil: 'networkidle' });
  await page.waitForTimeout(4000);
  await enableSemantics(page);

  await shot(page, '01-onboarding-language');
  await tapText(page, 'اردو');
  await shot(page, '02-onboarding-language-urdu');
  await tapText(page, 'English');
  await tapText(page, 'Continue');
  await shot(page, '03-onboarding-mode');
  await tapText(page, 'Big and Simple');
  await tapText(page, 'Continue');

  await shot(page, '04-sign-in-simple');
  await typeInto(page, 'Email', 'ammi@example.com');
  await typeInto(page, 'Password', 'Preview123x');
  await tapText(page, 'Sign in');
  await page.waitForTimeout(1500);

  await shot(page, '05-set-pin');
  for (const d of ['1', '2', '5', '8']) await tapText(page, d);
  await tapText(page, 'Continue');
  for (const d of ['1', '2', '5', '8']) await tapText(page, d);
  await shot(page, '06-confirm-pin');
  await tapText(page, 'Continue');
  await page.waitForTimeout(1500);

  await shot(page, '07-spaces-simple');
  await tapText(page, 'Settings');
  await shot(page, '08-settings');
  await tapText(page, 'Big and Simple mode');
  await tapText(page, 'اردو');
  await shot(page, '09-settings-urdu-standard');
  await page.goBack();
  await page.waitForTimeout(800);
  await shot(page, '10-spaces-urdu');

  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
