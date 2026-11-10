import puppeteer from 'puppeteer';
import { readFileSync } from 'node:fs';
import QRCode from 'qrcode';
import { buildCardsHtml } from './card-html.mjs';

const state = JSON.parse(readFileSync('demo-qr-state.json', 'utf8'));
const records = [];
for (const r of state.records) {
  const qrSvg = await QRCode.toString(r.qrContent, {
    type: 'svg',
    margin: 0,
    color: { dark: '#0A0E1A', light: '#FFFFFF' },
  });
  records.push({ qrCode: r.qrCode, qrSvg });
}

const browser = await puppeteer.launch();
const page = await browser.newPage();
await page.setViewport({ width: 924, height: 1302, deviceScaleFactor: 1 });
await page.setContent(buildCardsHtml(records, { zoom: 1 }), { waitUntil: 'networkidle0' });
await page.evaluate(() => document.fonts.ready);
const cards = await page.$$('.card');
for (let i = 0; i < records.length; i++) {
  await cards[i * 2].screenshot({ path: `check-${records[i].qrCode}.png` });
}
await browser.close();
console.log('Done.');
