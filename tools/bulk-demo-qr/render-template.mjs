// Renders ONE card pair (front + back) as PNG previews and a 2-page PDF at
// the exact physical card size, with the back rotated 180deg for mounting on
// a printer stand (reads correctly once the card is flipped top-to-bottom).
// Visual check only: it does not touch Firestore.  Run:  npm run template
import { readFileSync } from 'node:fs';
import QRCode from 'qrcode';
import puppeteer from 'puppeteer';
import { buildCardsHtml, CARD_PRINT_W_MM, CARD_PRINT_H_MM, CONTACT_PHONE } from './card-html.mjs';

const qrCode = process.argv[2] ?? 'QR121';
// Short real URL so the sample QR scans and has the density of a real one.
const content = process.argv[3] ?? 'https://fullstarqr.com/';

const qrSvg = await QRCode.toString(content, {
  type: 'svg',
  margin: 0,
  errorCorrectionLevel: 'M',
  color: { dark: '#0A0E1A', light: '#FFFFFF' },
});
const records = [{ qrCode, qrSvg, phone: CONTACT_PHONE }];

const mmToPx150 = (mm) => Math.round((mm / 25.4) * 150); // ~150dpi for both the PNG previews and the PDF-embedded images

const browser = await puppeteer.launch();
try {
  const page = await browser.newPage();
  const html = buildCardsHtml(records, { mode: 'print', mirrorBack: true });

  await page.setViewport({
    width: mmToPx150(CARD_PRINT_W_MM) + 20,
    height: mmToPx150(CARD_PRINT_H_MM) + 20,
    deviceScaleFactor: 300 / 96, // ~300dpi output for print
  });
  await page.setContent(html, { waitUntil: 'networkidle0' });
  await page.evaluate(() => document.fonts.ready);
  const cards = await page.$$('.card');
  await cards[0].screenshot({ path: 'template-front.png' });
  await cards[1].screenshot({ path: 'template-back.png' });

  // Build the PDF from the already-correct flat images instead of printing
  // the live (CSS-transformed) page directly: Chrome's print pagination can
  // clip transformed content below a certain point, but a plain <img> sized
  // with width/height (no transform) prints exactly as it looks on screen.
  const toDataUri = (p) => `data:image/png;base64,${readFileSync(p).toString('base64')}`;
  const pdfHtml = `<!doctype html><html><head><meta charset="utf-8"><style>
    @page { size: ${CARD_PRINT_W_MM}mm ${CARD_PRINT_H_MM}mm; margin: 0; }
    * { margin: 0; padding: 0; }
    .page { width: ${CARD_PRINT_W_MM}mm; height: ${CARD_PRINT_H_MM}mm; page-break-after: always; }
    .page:last-child { page-break-after: auto; }
    .page img { width: 100%; height: 100%; display: block; }
  </style></head><body>
    <div class="page"><img src="${toDataUri('template-front.png')}"></div>
    <div class="page"><img src="${toDataUri('template-back.png')}"></div>
  </body></html>`;
  await page.setContent(pdfHtml, { waitUntil: 'networkidle0' });
  await page.pdf({
    path: `template-${qrCode}.pdf`,
    printBackground: true,
    preferCSSPageSize: true,
  });
} finally {
  await browser.close();
}

console.log(`Wrote template-front.png, template-back.png, template-${qrCode}.pdf`);
console.log(`Card size: ${CARD_PRINT_W_MM}mm x ${CARD_PRINT_H_MM}mm. Back is rotated 180deg. QR encodes: ${content}`);
