// Screenshot a review page at phone size, logging console/network problems.
// Usage: node shot-review.mjs <url> <out.png> [tap]
import puppeteer from 'puppeteer';

const [url, out, tap] = process.argv.slice(2);
const browser = await puppeteer.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--disable-quic'] });
try {
  const page = await browser.newPage();
  page.on('console', (m) => { if (['error', 'warning'].includes(m.type())) console.log('[console]', m.type(), m.text().slice(0, 200)); });
  page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 200)));
  page.on('requestfailed', (r) => console.log('[requestfailed]', r.url().slice(0, 120), r.failure()?.errorText));
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  await page.goto(url, { waitUntil: 'networkidle2', timeout: 90000 });
  await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 60000 }).catch(() => console.log('[warn] no flutter view element found'));
  await new Promise((r) => setTimeout(r, 6000));
  if (tap) {
    await page.mouse.click(263, 380);
    await new Promise((r) => setTimeout(r, 1500));
  }
  await page.screenshot({ path: out });
  console.log('saved', out);
} finally {
  await browser.close();
}
