// Helpers to drive the Flutter web app through its accessibility (semantics) tree.
import puppeteer from 'puppeteer';

export const APP_URL = 'http://127.0.0.1:8081/';

// If the app ever calls a live Firebase service, the run is aborted: these tests
// must only ever talk to the local emulators.
const LIVE_HOSTS = [
  'firestore.googleapis.com',
  'identitytoolkit.googleapis.com',
  'securetoken.googleapis.com',
  'script.google.com',
  'firebaseinstallations.googleapis.com',
];

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function launch() {
  const browser = await puppeteer.launch({ args: ['--disable-quic'] });
  const context = await browser.createBrowserContext(); // fresh storage every run
  const page = await context.newPage();
  await page.setViewport({ width: 1280, height: 1000 });

  page.liveCalls = [];
  page.on('request', (req) => {
    const host = new URL(req.url()).hostname;
    if (LIVE_HOSTS.includes(host)) page.liveCalls.push(req.url());
  });
  page.pageErrors = [];
  page.step = 'start';
  page.on('pageerror', (e) =>
    page.pageErrors.push(`[after "${page.step}"] ${String(e.stack || e).slice(0, 700)}`),
  );
  return { browser, page };
}

export async function openApp(page) {
  await page.goto(APP_URL, { waitUntil: 'networkidle2', timeout: 60000 });
  await sleep(3000);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await sleep(1500);
}

export function assertNoLiveCalls(page) {
  if (page.liveCalls.length) {
    throw new Error(`ABORT: the app called a LIVE service: ${page.liveCalls.slice(0, 3).join(', ')}`);
  }
}

/** Text of every semantics node, containers included (so a card's text is found). */
export async function screenText(page) {
  return page.evaluate(() =>
    [...document.querySelectorAll('flt-semantics')]
      .flatMap((n) => [(n.textContent || '').trim(), (n.getAttribute('aria-label') || '').trim()])
      .filter(Boolean),
  );
}

/** Only the innermost nodes, e.g. one entry per button: for counting things. */
export async function leafText(page) {
  return page.evaluate(() =>
    [...document.querySelectorAll('flt-semantics')]
      .filter((n) => ![...n.children].some((c) => c.tagName === 'FLT-SEMANTICS'))
      .flatMap((n) => [(n.textContent || '').trim(), (n.getAttribute('aria-label') || '').trim()])
      .filter(Boolean),
  );
}

/** Values currently held by the visible text inputs. */
export async function inputValues(page) {
  return page.evaluate(() =>
    [...document.querySelectorAll('input, textarea')]
      .filter((i) => i.getBoundingClientRect().width > 0)
      .map((i) => i.value),
  );
}

export async function hasText(page, text) {
  const all = await screenText(page);
  return all.some((t) => t === text || t.includes(text));
}

export async function waitForText(page, text, timeout = 15000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    assertNoLiveCalls(page);
    if (await hasText(page, text)) return;
    await sleep(300);
  }
  const seen = (await screenText(page)).slice(0, 40).join(' | ');
  throw new Error(`Timed out waiting for "${text}". On screen: ${seen}`);
}

export async function waitForGone(page, text, timeout = 10000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    if (!(await hasText(page, text))) return;
    await sleep(300);
  }
  throw new Error(`"${text}" never went away.`);
}

/** Click the deepest semantics node whose text is exactly [text]. */
export async function tap(page, text, { nth = 0 } = {}) {
  const box = await page.evaluate(
    (text, nth) => {
      const nodes = [...document.querySelectorAll('flt-semantics')].filter((n) => {
        const own = (n.textContent || '').trim() === text || n.getAttribute('aria-label') === text;
        if (!own) return false;
        return ![...n.children].some(
          (c) => c.tagName === 'FLT-SEMANTICS' && (c.textContent || '').trim() === text,
        );
      });
      const el = nodes.at(nth);
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    },
    text,
    nth,
  );
  if (!box) {
    const seen = (await screenText(page)).slice(0, 40).join(' | ');
    throw new Error(`Could not find "${text}" to tap. On screen: ${seen}`);
  }
  await page.mouse.click(box.x, box.y);
  await sleep(700);
}

/** Type into the nth visible text input. */
export async function fill(page, index, value) {
  const handle = await page.evaluateHandle((index) => {
    const inputs = [...document.querySelectorAll('input, textarea')].filter((i) => {
      const r = i.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    });
    return inputs.at(index) || null;
  }, index);
  const el = handle.asElement();
  if (!el) throw new Error(`No text input at index ${index}`);
  await el.click();
  await sleep(200);
  await page.keyboard.down('Control');
  await page.keyboard.press('KeyA');
  await page.keyboard.up('Control');
  await page.keyboard.press('Backspace');
  await page.keyboard.type(value, { delay: 15 });
  await sleep(400);
}

export async function signIn(page, email, password) {
  await waitForText(page, 'Sign in');
  await fill(page, 0, email);
  await fill(page, 1, password);
  await tap(page, 'Sign in');
}

export async function signOut(page) {
  await tap(page, 'Logout');
  await waitForText(page, 'Sign in to your account', 15000);
}

export function check(name, ok, detail = '', page = null) {
  if (page) page.step = name;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` - ${detail}` : ''}`);
  if (!ok) process.exitCode = 1;
  return ok;
}
