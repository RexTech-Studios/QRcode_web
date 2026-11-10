import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fontsDir = path.resolve(__dirname, '../../landing/fonts').replace(/\\/g, '/');

export const CONTACT_PHONE = '+91 96057 98763';

// The design is drawn on a fixed 924 x 1302 px canvas; every position below
// is in that coordinate space. For actual printing it's non-uniformly scaled
// to the requested physical card size (so an exact width x height is honored
// even though it isn't the canvas's native aspect ratio).
export const CARD_W = 924;
export const CARD_H = 1302;
export const CARD_PRINT_W_MM = 100;
export const CARD_PRINT_H_MM = 150;
const mmToPx = (mm) => (mm / 25.4) * 96;

const BROWN = '#85561A';
const SPARK_PATH =
  'M12 0C12.9 7.2 16.8 11.1 24 12C16.8 12.9 12.9 16.8 12 24C11.1 16.8 7.2 12.9 0 12C7.2 11.1 11.1 7.2 12 0Z';
const STAR_POINTS =
  '12,1.5 14.9,8.6 22.5,9.2 16.7,14.2 18.5,21.6 12,17.6 5.5,21.6 7.3,14.2 1.5,9.2 9.1,8.6';

function mulberry32(seed) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Faint four-point sparkles in the top and bottom bands, as in the original.
function sparklePatternSvg() {
  const rand = mulberry32(121);
  const sizes = [7, 9, 11, 14, 18, 22];
  const bands = [
    { from: 4, to: 135, count: 46 },
    { from: 1108, to: 1204, count: 30 },
  ];
  let out = '';
  for (const band of bands) {
    for (let i = 0; i < band.count; i++) {
      const size = sizes[Math.floor(rand() * sizes.length)];
      const x = rand() * (CARD_W - size);
      const y = band.from + rand() * (band.to - band.from - size);
      const opacity = 0.35 + rand() * 0.55;
      out += `<svg x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${size}" height="${size}" viewBox="0 0 24 24" opacity="${opacity.toFixed(2)}"><path d="${SPARK_PATH}" fill="#E9E0CC"/></svg>`;
    }
  }
  return `<svg class="pattern" width="${CARD_W}" height="${CARD_H}" viewBox="0 0 ${CARD_W} ${CARD_H}">${out}</svg>`;
}

function fontFaceCss() {
  const f = (family, weight, file) => {
    const b64 = readFileSync(path.join(fontsDir, file)).toString('base64');
    return `@font-face { font-family: '${family}'; font-weight: ${weight}; src: url('data:font/woff2;base64,${b64}') format('woff2'); }`;
  };
  return [
    f('Playfair Display', 700, 'playfair-display-latin-700-normal.woff2'),
    f('Poppins', 400, 'poppins-latin-400-normal.woff2'),
    f('Poppins', 500, 'poppins-latin-500-normal.woff2'),
  ].join('\n');
}

// pxW/pxH: the final on-page size of each card, in CSS px. For 'print' mode
// this is the exact requested physical size (CARD_PRINT_W_MM/H_MM); for
// 'screenshot' mode (used when compositing a multi-up grid sheet elsewhere)
// it's the native design canvas, unscaled.
const css = (pxW, pxH) => `
  ${fontFaceCss()}
  @page { size: ${(pxW / 96) * 25.4}mm ${(pxH / 96) * 25.4}mm; margin: 0; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { background: #fff; }
  .card {
    position: relative; width: ${pxW}px; height: ${pxH}px; overflow: hidden;
    background: #FEFEFC; page-break-after: always; break-after: page;
  }
  .card:last-child { page-break-after: auto; break-after: auto; }
  .card.mirror { transform: rotate(180deg); }
  .card-face {
    position: absolute; left: 0; top: 0; width: ${CARD_W}px; height: ${CARD_H}px;
    transform-origin: top left; transform: scale(${pxW / CARD_W}, ${pxH / CARD_H});
    font-family: 'Poppins', Arial, sans-serif; color: #111;
  }
  .pattern { position: absolute; left: 0; top: 0; }
  .at { position: absolute; left: 0; width: ${CARD_W}px; display: flex; justify-content: center; align-items: center; transform: translateY(-50%); white-space: nowrap; }

  .eyebrow { top: 78px; gap: 12px; }
  .eyebrow .rule { width: 95px; height: 3px; background: ${BROWN}; }
  .eyebrow .txt { font-size: 23.5px; font-weight: 400; letter-spacing: 4.7px; color: #151515; }

  .brand { top: 155px; font: 700 36px/1 'Playfair Display', Georgia, serif; letter-spacing: 0.5px; color: #070707; }

  .stars { top: 194px; gap: 0; }
  .stars .rule { width: 52px; height: 3px; background: ${BROWN}; }
  .stars svg.star { width: 21px; height: 21px; margin: 0 0.5px; }

  .headline { top: 307px; flex-direction: column; font: 700 76.5px/80px 'Playfair Display', Georgia, serif; color: #070707; letter-spacing: 0.4px; }
  .sub { top: 475px; flex-direction: column; font-size: 31px; line-height: 47px; font-weight: 400; color: #0b0b0b; }

  .frame {
    position: absolute; left: 255px; top: 545px; width: 422px; height: 423px; border-radius: 36px;
    border: 8px solid transparent;
    background: linear-gradient(#fff, #fff) padding-box,
                linear-gradient(135deg, #DDB683 0%, #B58445 48%, #D9B078 100%) border-box;
    display: flex; align-items: center; justify-content: center;
  }
  .frame .qr { width: 351px; height: 351px; display: block; }
  .frame .qr svg { width: 100%; height: 100%; display: block; }
  .spark { position: absolute; width: 34px; height: 34px; }

  .cta {
    position: absolute; left: 246px; top: 993px; width: 434px; height: 80px; border-radius: 40px;
    background: linear-gradient(90deg, #BF8B47 0%, #D9AF76 35%, #C08C48 66%, #DCB278 100%);
    display: flex; align-items: center; justify-content: center;
    font-size: 36.5px; font-weight: 500; letter-spacing: 2.4px; color: #111; text-transform: uppercase;
  }

  .divider { top: 1100px; }
  .divider .line { width: 215px; height: 1.5px; }
  .divider .line.l { background: linear-gradient(90deg, rgba(198,156,93,0), rgba(198,156,93,.75)); }
  .divider .line.r { background: linear-gradient(90deg, rgba(198,156,93,.75), rgba(198,156,93,0)); }
  .divider svg { width: 22px; height: 22px; margin: 0 8px; }

  .share { top: 1143px; font-size: 23.3px; font-weight: 400; letter-spacing: 2.9px; color: #3F2A12; text-transform: uppercase; }

  .footer {
    position: absolute; left: 0; bottom: 0; width: ${CARD_W}px; height: 91px;
    background: linear-gradient(90deg, #C69E65 0%, #865B2F 22%, #A27646 60%, #C79F66 100%);
    display: flex; align-items: center; justify-content: center;
    font-size: 27.7px; font-weight: 400; letter-spacing: 3.1px; color: #fff; text-transform: uppercase;
  }

  .id { top: 955px; font: 400 43.5px/1 'Times New Roman', Times, serif; color: #000; }
  .contact { top: 1027px; font: 400 43.5px/1 'Times New Roman', Times, serif; color: #000; }
`;

const sparkle = (cls, style) =>
  `<svg class="${cls}" style="${style}" viewBox="0 0 24 24"><path d="${SPARK_PATH}" fill="#D9CAAE"/></svg>`;

const starIcon = `<svg class="star" viewBox="0 0 24 24"><polygon points="${STAR_POINTS}" fill="${BROWN}"/></svg>`;

function frontCard({ qrSvg }) {
  return `
  <div class="card"><div class="card-face">
    ${sparklePatternSvg()}
    <div class="at eyebrow"><span class="rule"></span><span class="txt">CUSTOMER FEEDBACK</span><span class="rule"></span></div>
    <div class="at brand">FULL STAR QR</div>
    <div class="at stars"><span class="rule"></span>${starIcon.repeat(5)}<span class="rule"></span></div>
    <div class="at headline"><span>Your Feedback</span><span>Matters</span></div>
    <div class="at sub"><span>We'd love to hear your thoughts.</span><span>Your feedback helps us serve you better.</span></div>
    ${sparkle('spark', 'left:193px; top:656px;')}
    ${sparkle('spark', 'left:693px; top:794px;')}
    <div class="frame"><div class="qr">${qrSvg}</div></div>
    <div class="cta">Scan to Review</div>
    <div class="at divider"><span class="line l"></span><svg viewBox="0 0 24 24"><path d="${SPARK_PATH}" fill="${BROWN}"/></svg><span class="line r"></span></div>
    <div class="at share">Share your experience</div>
    <div class="footer">Thank you for your time!</div>
  </div></div>`;
}

function backCard({ qrCode, phone, mirror }) {
  return `
  <div class="card${mirror ? ' mirror' : ''}"><div class="card-face">
    ${sparklePatternSvg()}
    <div class="at id">ID : ${qrCode}</div>
    <div class="at contact">Contact Us: ${phone}</div>
    <div class="at share">Share your experience</div>
    <div class="footer">Thank you for your time!</div>
  </div></div>`;
}

/**
 * records: [{ qrCode, qrSvg, phone? }].
 * mode: 'print' (exact CARD_PRINT_W_MM x CARD_PRINT_H_MM physical size, used
 *   for the actual printable PDF) or 'screenshot' (native 924x1302 canvas,
 *   used when compositing cards into a multi-up grid sheet elsewhere).
 * mirrorBack: flip the back card horizontally (for mounting methods where
 *   the back is viewed in reverse, e.g. taped to a stand).
 */
export function buildCardsHtml(records, { mode = 'print', mirrorBack = false } = {}) {
  const pxW = mode === 'print' ? mmToPx(CARD_PRINT_W_MM) : CARD_W;
  const pxH = mode === 'print' ? mmToPx(CARD_PRINT_H_MM) : CARD_H;
  const pages = records
    .map((r) => frontCard(r) + backCard({ qrCode: r.qrCode, phone: r.phone ?? CONTACT_PHONE, mirror: mirrorBack }))
    .join('\n');
  return `<!doctype html><html><head><meta charset="utf-8"><style>${css(pxW, pxH)}</style></head><body>${pages}</body></html>`;
}

