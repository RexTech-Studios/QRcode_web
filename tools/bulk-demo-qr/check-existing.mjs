// Read-only: reports the current highest QR### in Firestore and whether any
// number in demo-qr-state.json would collide. Writes nothing.
import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const keyPath = process.argv[2];
if (!keyPath) {
  console.error('Usage: node check-existing.mjs <path-to-service-account.json>');
  process.exit(1);
}

const serviceAccount = JSON.parse(readFileSync(keyPath, 'utf8'));
initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

const snap = await db.collection('qr_codes').get();
let highest = 0;
const usedNumbers = new Set();
for (const doc of snap.docs) {
  const qrCode = doc.data().qrCode;
  const m = /^QR(\d+)$/.exec(qrCode ?? '');
  if (m) {
    usedNumbers.add(Number(m[1]));
    highest = Math.max(highest, Number(m[1]));
  }
}

console.log(`Total QR records in Firestore: ${snap.size}`);
console.log(`Highest existing QR number: QR${highest}`);
console.log(`Next free number: QR${highest + 1}`);

const state = JSON.parse(readFileSync('demo-qr-state.json', 'utf8'));
const collisions = state.records.filter((r) => {
  const m = /^QR(\d+)$/.exec(r.qrCode);
  return m && usedNumbers.has(Number(m[1]));
});

console.log(`\nLocally prepared records: ${state.records.length} (${state.records.map((r) => r.qrCode).join(', ')})`);
if (collisions.length) {
  console.log(`COLLISION: these already exist in Firestore and must be renumbered: ${collisions.map((c) => c.qrCode).join(', ')}`);
} else {
  console.log('No collisions — all locally prepared numbers are free.');
}
