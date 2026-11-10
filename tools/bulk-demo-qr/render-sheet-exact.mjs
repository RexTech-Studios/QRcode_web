// Multi-up sheet of cards at the EXACT physical card size (100x150mm),
// fronts on page 1 and backs (upright, columns right-to-left) on page 2.
// Back columns are reversed per row so each back sits directly behind its
// front when the sheet is printed double-sided (flip on long edge).
// Usage: node render-sheet-exact.mjs <cols> <rows> <offset> [marginMm] [gapMm]
import { readFileSync, mkdirSync } from 'node:fs';
import QRCode from 'qrcode';
import puppeteer from 'puppeteer';
import { buildCardsHtml, CARD_PRINT_W_MM, CARD_PRINT_H_MM } from './card-html.mjs';

const COLS = Number(process.argv[2] ?? 3);
const ROWS = Number(process.argv[3] ?? 3);
const OFFSET = Number(process.argv[4] ?? 0);
const MARGIN = Number(process.argv[5] ?? 10);
const GAP = Number(process.argv[6] ?? 4);
const COUNT = COLS * ROWS;

const PAGE_W = COLS * CARD_PRINT_W_MM + (COLS - 1) * GAP + 2 * MARGIN;
const PAGE_H = ROWS * CARD_PRINT_H_MM + (ROWS - 1) * GAP + 2 * MARGIN;

const state = JSON.parse(readFileSync('demo-qr-state.json', 'utf8'));
const records = state.records.filter((r) => r.writtenToFirestore).slice(OFFSET, OFFSET + COUNT);
if (records.length === 0) throw new Error('No records for this offset.');

mkdirSync('exact-cells', { recursive: true });

const browser = await puppeteer.launch();
const page = await browser.newPage();
await page.setViewport({ width: 500, height: 800, deviceScaleFactor: 300 / 96 });

const cells = [];
for (const r of records) {
  const qrSvg = await QRCode.toString(r.qrContent, {
    type: 'svg',
    margin: 0,
    errorCorrectionLevel: 'M',
    color: { dark: '#0A0E1A', light: '#FFFFFF' },
  });
  await page.setContent(
    buildCardsHtml([{ qrCode: r.qrCode, qrSvg, phone: r.phone }], { mode: 'print', mirrorBack: false }),
    { waitUntil: 'networkidle0' }
  );
  await page.evaluate(() => document.fonts.ready);
  const els = await page.$$('.card');
  const front = `exact-cells/${r.qrCode}-front.png`;
  const back = `exact-cells/${r.qrCode}-back.png`;
  await els[0].screenshot({ path: front });
  await els[1].screenshot({ path: back });
  cells.push({ qrCode: r.qrCode, front, back });
}

const uri = (p) => `data:image/png;base64,${readFileSync(p).toString('base64')}`;

function sheet(images, reverseColumns) {
  const slots = Array.from({ length: COUNT }, (_, i) => images[i] ?? null);
  const ordered = [];
  for (let row = 0; row < ROWS; row++) {
    const rowSlots = slots.slice(row * COLS, (row + 1) * COLS);
    ordered.push(...(reverseColumns ? rowSlots.reverse() : rowSlots));
  }
  const html = ordered
    .map((img) => `<div class="cell">${img ? `<img src="${uri(img)}">` : ''}</div>`)
    .join('');
  return `<div class="sheet">${html}</div>`;
}

const css = `
  @page { size: ${PAGE_W}mm ${PAGE_H}mm; margin: 0; }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: ${PAGE_W}mm; }
  .sheet {
    width: ${PAGE_W}mm; height: ${PAGE_H}mm; padding: ${MARGIN}mm;
    display: grid; grid-template-columns: repeat(${COLS}, ${CARD_PRINT_W_MM}mm);
    grid-template-rows: repeat(${ROWS}, ${CARD_PRINT_H_MM}mm); gap: ${GAP}mm;
    page-break-after: always; break-after: page; background: #fff;
  }
  .sheet:last-child { page-break-after: auto; break-after: auto; }
  .cell { width: ${CARD_PRINT_W_MM}mm; height: ${CARD_PRINT_H_MM}mm; }
  .cell img { width: 100%; height: 100%; display: block; }
`;

const html = `<!doctype html><html><head><meta charset="utf-8"><style>${css}</style></head><body>
  ${sheet(cells.map((c) => c.front), false)}
  ${sheet(cells.map((c) => c.back), true)}
</body></html>`;

const label = `${records[0].qrCode}-${records[records.length - 1].qrCode}`;
await page.setContent(html, { waitUntil: 'networkidle0' });
await page.pdf({ path: `sheet-${COLS}x${ROWS}-${label}.pdf`, printBackground: true, preferCSSPageSize: true });

// Flat previews of each sheet page.
const mmPx = (mm) => Math.round((mm / 25.4) * 96);
await page.setViewport({ width: mmPx(PAGE_W), height: mmPx(PAGE_H), deviceScaleFactor: 1 });
const sheets = await page.$$('.sheet');
await sheets[0].screenshot({ path: 'sheet-preview-front.png' });
await sheets[1].screenshot({ path: 'sheet-preview-back.png' });
await browser.close();

console.log(`Wrote sheet-${COLS}x${ROWS}-${label}.pdf (${records.length}/${COUNT} cards), page ${PAGE_W}x${PAGE_H}mm, 2 pages.`);
