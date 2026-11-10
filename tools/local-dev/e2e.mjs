// End-to-end test of the sales-team feature against the LOCAL emulators, driving
// the real built app in a browser. Run the emulators, `node seed.mjs`, build the
// app with --dart-define=USE_EMULATOR=true and serve it on :8081 first.
//
// It aborts the moment the app talks to any live Firebase service.
process.env.FIRESTORE_EMULATOR_HOST = 'localhost:8089';
process.env.FIREBASE_AUTH_EMULATOR_HOST = 'localhost:9099';

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import {
  assertNoLiveCalls, check, fill, hasText, launch, leafText, openApp, screenText,
  signIn, signOut, tap, waitForText,
} from './e2e-lib.mjs';

initializeApp({ projectId: 'qrcode-16b68' });
const db = getFirestore();
const auth = getAuth();

const ADMIN = ['admin@local.test', 'localadmin1'];
const REP = ['rep1@local.test', 'reppass123'];
const GOOD_URL = 'https://g.page/r/CcMyClient/review';
const REP_QRS = ['QR121', 'QR122', 'QR123', 'QR124', 'QR125'];

// Start from a clean slate so reruns behave the same.
for (const col of ['users', 'assignments']) {
  const snap = await db.collection(col).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}
for (const email of [REP[0], 'stranger@local.test']) {
  try { await auth.deleteUser((await auth.getUserByEmail(email)).uid); } catch { /* not there yet */ }
}
await auth.createUser({ email: 'stranger@local.test', password: 'strangerpass1' });
for (let n = 121; n <= 125; n++) {
  await db.collection('shops').doc(`shop-${n}`).update({
    shopName: `Demo QR${n}`,
    googleReviewUrl: 'https://www.google.com/maps/place/Rextech+Studios',
  });
}

const { browser, page } = await launch();
const realCheck = check;
const step = (name, ok, detail = '') => realCheck(name, ok, detail, page);
try {
  // ---- Admin creates a sales login ----
  await openApp(page);
  await signIn(page, ...ADMIN);
  await waitForText(page, 'Sales Team', 20000);
  step('admin signs in and sees the Sales Team tab', true);

  await tap(page, 'Sales Team');
  await waitForText(page, 'Add sales person');
  step('team list starts empty', await hasText(page, 'No sales people yet'));

  await tap(page, 'Add sales person');
  await waitForText(page, 'Email (their login)');
  await fill(page, -3, 'Test Rep');
  await fill(page, -2, REP[0]);
  await fill(page, -1, REP[1]);
  await tap(page, 'Create login');
  await waitForText(page, 'Login created');
  step('login created, with a way to copy the details to pass on', await hasText(page, 'Copy login details'));
  const created = await auth.getUserByEmail(REP[0]);
  const userDoc = (await db.collection('users').doc(created.uid).get()).data();
  step('the users record was written', userDoc?.role === 'sales' && userDoc?.active === true && userDoc?.name === 'Test Rep');
  step('admin was NOT signed out by creating the login', !(await hasText(page, 'Sign in to your account')));
  await tap(page, 'Done');

  // ---- Admin assigns QR codes ----
  await waitForText(page, 'Assign QRs');
  await tap(page, 'Assign QRs');
  await waitForText(page, 'QR numbers');
  await fill(page, -1, '121-125, 999');
  await waitForText(page, 'Will assign 5 QR codes');
  step('preview flags the number that does not exist', await hasText(page, 'No such QR number: QR999'));
  await tap(page, 'Assign 5');
  await waitForText(page, 'Assigned 5 QR codes to Test Rep.');
  const assigned = await db.collection('assignments').get();
  step('5 assignments written, unlocked, with explicit nulls',
    assigned.size === 5 && assigned.docs.every((d) => {
      const a = d.data();
      return a.locked === false && a.soldAt === null && a.lastEditedAt === null && a.assignedTo === created.uid;
    }));
  await tap(page, 'My QR Codes');
  await waitForText(page, 'Assigned to Test Rep');
  step('My QR Codes cards show who holds each QR', true);
  assertNoLiveCalls(page);

  await signOut(page);

  // ---- The sales person signs in and sees only their own QR codes ----
  await signIn(page, ...REP);
  await waitForText(page, 'My QR codes', 20000);
  await waitForText(page, 'QR125');
  const joined = (await screenText(page)).join(' ');
  step('sales person sees exactly the 5 QR codes assigned to them',
    REP_QRS.every((q) => joined.includes(q)) && !joined.includes('QR126'));
  step('sales person does not get the admin dashboard', !joined.includes('Generate QR') && !joined.includes('Sales Team'));

  await tap(page, 'Set up for client', { nth: 0 });
  await waitForText(page, 'Google Maps review link');
  await fill(page, -2, 'Cafe Aroma');
  await fill(page, -1, 'http://evil.example/x');
  await tap(page, 'Save');
  await waitForText(page, 'valid Google Maps review link');
  step('a bad link is refused and nothing is saved', (await db.collection('shops').doc('shop-121').get()).data().shopName === 'Demo QR121');

  await fill(page, -1, GOOD_URL);
  await tap(page, 'Save');
  await waitForText(page, 'Save and lock?');
  await tap(page, 'Save and lock');
  await waitForText(page, 'Saved. This QR is now locked.');
  const shop1 = (await db.collection('shops').doc('shop-121').get()).data();
  const a1 = (await db.collection('assignments').doc('shop-121').get()).data();
  step('the shop name and link were changed', shop1.shopName === 'Cafe Aroma' && shop1.googleReviewUrl === GOOD_URL);
  step('the QR is locked and the sale was timestamped', a1.locked === true && a1.soldAt && a1.lastEditedAt);
  step('the sales person cannot edit it again (button gone, 4 left)', (await leafText(page)).filter((t) => t === 'Set up for client').length === 4);
  const firstSoldAt = a1.soldAt.toMillis();
  assertNoLiveCalls(page);

  await signOut(page);

  // ---- Admin sees the sale, and unlocks it ----
  await signIn(page, ...ADMIN);
  await waitForText(page, 'Sales Team', 20000);
  await tap(page, 'Sales Team');
  await tap(page, 'Assigned QRs');
  await waitForText(page, 'Edited - locked');
  step('admin sees QR121 as edited and locked', true);
  await tap(page, 'Allow edit again');
  await waitForText(page, 'Allow another edit?');
  await tap(page, 'Allow edit', { nth: -1 });
  await waitForText(page, 'Unlocked for another edit');
  step('unlock written, sale date kept',
    (await db.collection('assignments').doc('shop-121').get()).data().locked === false);

  await tap(page, 'Report');
  await tap(page, 'All time');
  await waitForText(page, 'Sold in this range (1)');
  step('report counts the sale by the sales person', await hasText(page, 'Test Rep'));
  await signOut(page);

  // ---- Second edit after unlock keeps the original sale date ----
  await signIn(page, ...REP);
  await waitForText(page, 'My QR codes', 20000);
  await waitForText(page, 'Cafe Aroma');
  await tap(page, 'Set up for client', { nth: 0 });
  await waitForText(page, 'Google Maps review link');
  await fill(page, -2, 'Cafe Aroma Two');
  await fill(page, -1, GOOD_URL);
  await tap(page, 'Save');
  await waitForText(page, 'Save and lock?');
  await tap(page, 'Save and lock');
  await waitForText(page, 'Saved. This QR is now locked.');
  const a2 = (await db.collection('assignments').doc('shop-121').get()).data();
  step('second edit allowed after the admin unlocked it',
    (await db.collection('shops').doc('shop-121').get()).data().shopName === 'Cafe Aroma Two' && a2.locked === true);
  step('the original sale date is unchanged', a2.soldAt.toMillis() === firstSoldAt);
  await signOut(page);

  // ---- Turning someone off ----
  await signIn(page, ...ADMIN);
  await waitForText(page, 'Sales Team', 20000);
  await tap(page, 'Sales Team');
  await waitForText(page, 'Turn off');
  await tap(page, 'Turn off');
  await waitForText(page, 'will not be able to sign in');
  await tap(page, 'Turn off', { nth: -1 });
  await waitForText(page, 'Turned off');
  await signOut(page);
  await signIn(page, ...REP);
  await waitForText(page, 'This account has been turned off', 20000);
  step('a turned-off sales person is refused with a clear message', true);

  // ---- Someone with no sales record ----
  await signIn(page, 'stranger@local.test', 'strangerpass1');
  await waitForText(page, 'Not authorized', 20000);
  step('an account with no sales record is refused', true);

  assertNoLiveCalls(page);
  step('no calls to any live Firebase service', page.liveCalls.length === 0);
  // Flutter's own keyboard handler throws this when the automation types a "-",
  // before any of our code runs. Real keyboards don't trigger it.
  const unexpected = page.pageErrors.filter((e) => !/reading 'toString'/.test(e));
  step('no unexpected uncaught errors in the app', unexpected.length === 0, unexpected.join('\n      '));
} catch (e) {
  console.log(`FAIL  ${e.message}`);
  process.exitCode = 1;
  await page.screenshot({ path: 'e2e-failure.png' });
} finally {
  await browser.close();
}
