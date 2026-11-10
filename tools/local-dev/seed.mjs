// Fills the LOCAL Firebase emulators with test data: the admin login, plus 20
// demo shops and QR codes (QR121-QR140). It refuses to run unless the emulator
// addresses are set, so it can never write to the live project.
//
//   $env:FIRESTORE_EMULATOR_HOST = 'localhost:8089'
//   $env:FIREBASE_AUTH_EMULATOR_HOST = 'localhost:9099'
//   node seed.mjs
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error('Refusing to run: FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST must both be set.');
  process.exit(1);
}
for (const host of [process.env.FIRESTORE_EMULATOR_HOST, process.env.FIREBASE_AUTH_EMULATOR_HOST]) {
  if (!/^(localhost|127\.0\.0\.1)(:\d+)?$/.test(host)) {
    console.error(`Refusing to run: "${host}" is not a local address.`);
    process.exit(1);
  }
}

// Same uid as AppConfig.adminUid and firestore.rules.
export const ADMIN_UID = '7HVKqxlkuiafMK6XVL9SOmGieph2';
export const ADMIN_EMAIL = 'admin@local.test';
export const ADMIN_PASSWORD = 'localadmin1';

initializeApp({ projectId: 'qrcode-16b68' });
const auth = getAuth();
const db = getFirestore();

// Start from a clean slate, so running this again resets everything.
for (const collection of ['users', 'assignments', 'feedback', 'shops', 'qr_codes']) {
  const snap = await db.collection(collection).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}
for (const user of (await auth.listUsers(1000)).users) {
  if (user.uid !== ADMIN_UID) await auth.deleteUser(user.uid);
}

try {
  await auth.getUser(ADMIN_UID);
  await auth.updateUser(ADMIN_UID, { email: ADMIN_EMAIL, password: ADMIN_PASSWORD });
} catch {
  await auth.createUser({ uid: ADMIN_UID, email: ADMIN_EMAIL, password: ADMIN_PASSWORD });
}

const now = new Date().toISOString();
const batch = db.batch();
for (let n = 121; n <= 140; n++) {
  batch.set(db.collection('shops').doc(`shop-${n}`), {
    shopId: `shop-${n}`,
    shopName: `Demo QR${n}`,
    shopLogo: null,
    googleReviewUrl: 'https://www.google.com/maps/place/Rextech+Studios',
    createdAt: now,
    googleSheetsUrl: null,
    qrCode: `QR${n}`,
  });
  batch.set(db.collection('qr_codes').doc(`qr-${n}`), {
    qrId: `qr-${n}`,
    shopId: `shop-${n}`,
    qrContent: `https://qrcode-16b68.web.app/#/review/shop-${n}`,
    qrLabel: 'Review us on Google',
    qrStyle: 'classic',
    createdAt: now,
    updatedAt: null,
    qrCode: `QR${n}`,
  });
}
await batch.commit();

console.log(`Seeded the emulators. Admin login: ${ADMIN_EMAIL} / ${ADMIN_PASSWORD}`);
console.log('20 demo shops and QR codes: QR121 to QR140.');
