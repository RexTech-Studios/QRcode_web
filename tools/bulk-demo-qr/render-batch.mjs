// Renders N card pairs using the REAL review-URL format the app uses, with
// freshly generated UUIDs saved to a local state file so the same IDs can be
// written to Firestore later (no duplicate / mismatched records).
// Does NOT touch Firestore. Run:  node render-batch.mjs <count> <startNumber>
import { randomUUID } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import QRCode from 'qrcode';
import puppeteer from 'puppeteer';
import { buildCardsHtml, CONTACT_PHONE } from './card-html.mjs';

const COUNT = Number(process.argv[2] ?? 3);
const START = Number(process.argv[3] ?? 121);
const STATE_FILE = 'demo-qr-state.json';

// Same URL shape as QrService.buildReviewPageUrl / AppConfig.reviewUrl
// with useNewDomain = false (lib/utils/app_config.dart).
const reviewUrl = (shopId) => `https://qrcode-16b68.web.app/#/review/${shopId}`;

const state = existsSync(STATE_FILE)
  ? JSON.parse(readFileSync(STATE_FILE, 'utf8'))
  : { records: [] };

const existingNumbers = new Set(state.records.map((r) => r.qrCode));

const batch = [];
for (let i = 0; i < COUNT; i++) {
  const qrCode = `QR${START + i}`;
  if (existingNumbers.has(qrCode)) {
    console.log(`Skipping ${qrCode} — already in ${STATE_FILE} from an earlier run.`);
    continue;
  }
  const shopId = randomUUID();
  const qrId = randomUUID();
  const content = reviewUrl(shopId);
  batch.push({
    qrCode,
    shopId,
    qrId,
    qrContent: content,
    shopName: `Demo ${qrCode}`,
    googleReviewUrl:
      'https://www.google.com/maps/place/Rextech+Studios/@10.0088658,76.3651329,858m/data=!3m1!1e3!4m8!3m7!1s0x3b080dee8994f15f:0x1c69bec677aecbe2!8m2!3d10.0088658!4d76.3651329!9m1!1b1!16s%2Fg%2F11vzs536tj!5m1!1e2',
    phone: CONTACT_PHONE,
    createdAt: new Date().toISOString(),
    writtenToFirestore: false,
  });
}

if (batch.length === 0) {
  console.log('Nothing new to render.');
  process.exit(0);
}

// Render SVG QR for each, then build the printable HTML.
const records = [];
for (const r of batch) {
  const qrSvg = await QRCode.toString(r.qrContent, {
    type: 'svg',
    margin: 0,
    errorCorrectionLevel: 'M',
    color: { dark: '#0A0E1A', light: '#FFFFFF' },
  });
  records.push({ qrCode: r.qrCode, qrSvg, phone: r.phone });
}

const browser = await puppeteer.launch();
try {
  const page = await browser.newPage();
  await page.setContent(buildCardsHtml(records), { waitUntil: 'networkidle0' });
  await page.evaluate(() => document.fonts.ready);
  const outFile = `batch-${batch[0].qrCode}-${batch[batch.length - 1].qrCode}.pdf`;
  await page.pdf({ path: outFile, printBackground: true, preferCSSPageSize: true });
  console.log(`Wrote ${outFile} (${batch.length} pairs, ${batch.length * 2} pages)`);
} finally {
  await browser.close();
}

state.records.push(...batch);
writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
console.log(`Saved ${batch.length} record(s) to ${STATE_FILE} (not yet written to Firestore).`);
for (const r of batch) console.log(`  ${r.qrCode} -> shopId ${r.shopId}`);
