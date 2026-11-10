// Composes already-rendered front/back card PNGs into A4 duplex sheets:
// page 1 = N card fronts in a cols x rows grid, page 2 = the matching backs
// at IDENTICAL grid positions, for double-sided printing (flip long edge).
// Usage: node render-grid-sheet.mjs <cols> <rows> [marginMm] [gapMm]
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import QRCode from 'qrcode';
import puppeteer from 'puppeteer';
import { buildCardsHtml, CARD_W, CARD_H } from './card-html.mjs';

const COLS = Number(process.argv[2] ?? 2);
const ROWS = Number(process.argv[3] ?? 4);
const MARGIN_MM = Number(process.argv[4] ?? 8);
const GAP_MM = Number(process.argv[5] ?? 4);
const PAGE_W_MM = Number(process.argv[6] ?? 210);
const PAGE_H_MM = Number(process.argv[7] ?? 297);
const COUNT = COLS * ROWS;

const SKIP = Number(process.argv[8] ?? 0);
const state = JSON.parse(readFileSync('demo-qr-state.json', 'utf8'));
const written = state.records.filter((r) => r.writtenToFirestore);
const records = written.slice(SKIP, SKIP + COUNT);
if (records.length < COUNT) {
  console.warn(`Only ${records.length} written records available for this sheet (asked for ${COUNT}, starting at offset ${SKIP}). Remaining cells left blank.`);
}

mkdirSync('grid-cells', { recursive: true });

// Step 1: render each card's front and back to its own PNG, at full card
// resolution, exactly as already verified in the single-card template.
const browser = await puppeteer.launch();
const page = await browser.newPage();
await page.setViewport({ width: CARD_W, height: CARD_H, deviceScaleFactor: 2 });

const cellImages = [];
for (const r of records) {
  const qrSvg = await QRCode.toString(r.qrContent, {
    type: 'svg',
    margin: 0,
    errorCorrectionLevel: 'M',
    color: { dark: '#0A0E1A', light: '#FFFFFF' },
  });
  await page.setContent(buildCardsHtml([{ qrCode: r.qrCode, qrSvg, phone: r.phone }], { zoom: 1 }), {
    waitUntil: 'networkidle0',
  });
  await page.evaluate(() => document.fonts.ready);
  const cards = await page.$$('.card');
  const frontPath = `grid-cells/${r.qrCode}-front.png`;
  const backPath = `grid-cells/${r.qrCode}-back.png`;
  await cards[0].screenshot({ path: frontPath });
  await cards[1].screenshot({ path: backPath });
  cellImages.push({ qrCode: r.qrCode, frontPath, backPath });
}
await browser.close();

// Step 2: compose a cols x rows CSS grid at A4 size, images scaled with
// object-fit: contain so every card keeps its exact aspect ratio and is
// centered in its cell. Same grid markup is reused for both pages so
// coordinates are pixel-identical -> correct duplex alignment.
function toDataUri(path) {
  return `data:image/png;base64,${readFileSync(path).toString('base64')}`;
}

function gridPage(images, altText) {
  const cells = Array.from({ length: COUNT }, (_, i) => {
    const img = images[i];
    if (!img) return '<div class="cell"></div>';
    return `<div class="cell"><img src="${toDataUri(img)}" alt="${altText}"></div>`;
  }).join('\n');
  return `<div class="sheet">${cells}</div>`;
}

const gridCss = `
  @page { size: ${PAGE_W_MM}mm ${PAGE_H_MM}mm; margin: 0; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { width: ${PAGE_W_MM}mm; height: ${PAGE_H_MM}mm; }
  .sheet {
    width: ${PAGE_W_MM}mm; height: ${PAGE_H_MM}mm; padding: ${MARGIN_MM}mm;
    display: grid; grid-template-columns: repeat(${COLS}, 1fr); grid-template-rows: repeat(${ROWS}, 1fr);
    gap: ${GAP_MM}mm; page-break-after: always; break-after: page;
  }
  .sheet:last-child { page-break-after: auto; break-after: auto; }
  .cell { display: flex; align-items: center; justify-content: center; overflow: hidden; }
  .cell img { max-width: 100%; max-height: 100%; object-fit: contain; display: block; }
`;

const html = `<!doctype html><html><head><meta charset="utf-8"><style>${gridCss}</style></head><body>
  ${gridPage(cellImages.map((c) => c.frontPath), 'QR front')}
  ${gridPage(cellImages.map((c) => c.backPath), 'QR back')}
</body></html>`;

const browser2 = await puppeteer.launch();
try {
  const p = await browser2.newPage();
  await p.setContent(html, { waitUntil: 'networkidle0' });
  const rangeLabel = records.length ? `${records[0].qrCode}-${records[records.length - 1].qrCode}` : `offset${SKIP}`;
  const outFile = `sheet-${rangeLabel}.pdf`;
  await p.pdf({ path: outFile, printBackground: true, preferCSSPageSize: true });
  console.log(`Wrote ${outFile}: ${COLS} cols x ${ROWS} rows (${records.length}/${COUNT} cells filled), ${PAGE_W_MM}x${PAGE_H_MM}mm, 2 pages.`);
} finally {
  await browser2.close();
}
