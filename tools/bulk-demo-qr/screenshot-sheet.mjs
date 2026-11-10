// Re-renders the same grid HTML as render-grid-sheet.mjs but takes PNG
// screenshots of each full sheet page instead of a PDF, for visual review
// and QR decode verification.
import { readFileSync } from 'node:fs';
import puppeteer from 'puppeteer';

const cols = Number(process.argv[2] ?? 2);
const rows = Number(process.argv[3] ?? 4);
const marginMm = Number(process.argv[4] ?? 8);
const gapMm = Number(process.argv[5] ?? 4);
const pageWMm = Number(process.argv[6] ?? 210);
const pageHMm = Number(process.argv[7] ?? 297);
const count = cols * rows;

const state = JSON.parse(readFileSync('demo-qr-state.json', 'utf8'));
const records = state.records.filter((r) => r.writtenToFirestore).slice(0, count);

function toDataUri(path) {
  return `data:image/png;base64,${readFileSync(path).toString('base64')}`;
}

function gridPage(images) {
  const cells = Array.from({ length: count }, (_, i) => {
    const img = images[i];
    if (!img) return '<div class="cell"></div>';
    return `<div class="cell"><img src="${toDataUri(img)}"></div>`;
  }).join('\n');
  return `<div class="sheet">${cells}</div>`;
}

const gridCss = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { width: ${pageWMm}mm; height: ${pageHMm}mm; }
  .sheet {
    width: ${pageWMm}mm; height: ${pageHMm}mm; padding: ${marginMm}mm;
    display: grid; grid-template-columns: repeat(${cols}, 1fr); grid-template-rows: repeat(${rows}, 1fr);
    gap: ${gapMm}mm;
  }
  .cell { display: flex; align-items: center; justify-content: center; overflow: hidden; }
  .cell img { max-width: 100%; max-height: 100%; object-fit: contain; display: block; }
`;

const frontHtml = `<!doctype html><html><head><meta charset="utf-8"><style>${gridCss}</style></head><body>${gridPage(
  records.map((r) => `grid-cells/${r.qrCode}-front.png`)
)}</body></html>`;
const backHtml = `<!doctype html><html><head><meta charset="utf-8"><style>${gridCss}</style></head><body>${gridPage(
  records.map((r) => `grid-cells/${r.qrCode}-back.png`)
)}</body></html>`;

const browser = await puppeteer.launch();
const page = await browser.newPage();
// ~150dpi preview
const mmToPx = (mm) => Math.round((mm / 25.4) * 150);
await page.setViewport({ width: mmToPx(pageWMm), height: mmToPx(pageHMm), deviceScaleFactor: 1 });

await page.setContent(frontHtml, { waitUntil: 'networkidle0' });
await page.evaluate(() => document.fonts.ready);
await page.screenshot({ path: 'sheet-front.png' });

await page.setContent(backHtml, { waitUntil: 'networkidle0' });
await page.evaluate(() => document.fonts.ready);
await page.screenshot({ path: 'sheet-back.png' });

await browser.close();
console.log('Wrote sheet-front.png, sheet-back.png');
