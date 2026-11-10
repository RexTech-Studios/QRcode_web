// Writes the records in demo-qr-state.json to Firestore for real: creates
// the shop doc, the qr_codes doc, and the shop's Google Sheet via the same
// Apps Script endpoint the app itself uses. Safe to re-run: records already
// marked writtenToFirestore are skipped.
import { readFileSync, writeFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const keyPath = process.argv[2];
if (!keyPath) {
  console.error('Usage: node generate.mjs <path-to-service-account.json>');
  process.exit(1);
}

// Same endpoint as lib/services/google_sheets_service.dart's _scriptUrl.
const SCRIPT_URL =
  'https://script.google.com/macros/s/AKfycbyJdIi4WKBNTD9DSAuOnc9fv3uQsD9u9gssGMRGmum25XVmB4lOrfCl66ihy5ObhspopQ/exec';

const serviceAccount = JSON.parse(readFileSync(keyPath, 'utf8'));
initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

const STATE_FILE = 'demo-qr-state.json';
const state = JSON.parse(readFileSync(STATE_FILE, 'utf8'));

// Re-check for collisions right before writing (belt and suspenders).
const existingSnap = await db.collection('qr_codes').get();
const existingNumbers = new Set();
for (const doc of existingSnap.docs) {
  const m = /^QR(\d+)$/.exec(doc.data().qrCode ?? '');
  if (m) existingNumbers.add(Number(m[1]));
}

const toWrite = state.records.filter((r) => !r.writtenToFirestore);
if (toWrite.length === 0) {
  console.log('Nothing to write — all records already marked writtenToFirestore.');
  process.exit(0);
}

for (const r of toWrite) {
  const m = /^QR(\d+)$/.exec(r.qrCode);
  if (m && existingNumbers.has(Number(m[1]))) {
    console.error(`ABORT: ${r.qrCode} already exists in Firestore. Nothing written for this record.`);
    continue;
  }

  console.log(`Creating Google Sheet for "${r.shopName}"...`);
  let sheetsUrl = null;
  try {
    const res = await fetch(SCRIPT_URL, {
      method: 'POST',
      body: JSON.stringify({ action: 'create_sheet', shopName: r.shopName }),
    });
    const body = await res.json();
    if (body.url) {
      sheetsUrl = body.url;
      console.log(`  Sheet created: ${sheetsUrl}`);
    } else {
      console.warn(`  Sheet creation failed for ${r.qrCode}: ${body.error ?? 'no url returned'} — continuing without a sheet, same as the app does on this failure.`);
    }
  } catch (e) {
    console.warn(`  Could not reach the sheet service for ${r.qrCode}: ${e} — continuing without a sheet.`);
  }

  await db.collection('shops').doc(r.shopId).set({
    shopId: r.shopId,
    shopName: r.shopName,
    shopLogo: null,
    googleReviewUrl: r.googleReviewUrl,
    createdAt: r.createdAt,
    googleSheetsUrl: sheetsUrl,
    qrCode: r.qrCode,
  });

  await db.collection('qr_codes').doc(r.qrId).set({
    qrId: r.qrId,
    shopId: r.shopId,
    qrContent: r.qrContent,
    qrLabel: 'Review us on Google',
    qrStyle: 'classic',
    createdAt: r.createdAt,
    updatedAt: null,
    qrCode: r.qrCode,
  });

  r.writtenToFirestore = true;
  r.googleSheetsUrl = sheetsUrl;
  console.log(`  ${r.qrCode} written to Firestore (shop ${r.shopId}).`);
}

writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
console.log('\nDone. State file updated.');
