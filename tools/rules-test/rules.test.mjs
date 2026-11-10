// Firestore security rules tests. Run from the repo root with the emulator:
//   firebase emulators:exec --only firestore --project demo-rules "node --test tools/rules-test/rules.test.mjs"
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const ADMIN_UID = '7HVKqxlkuiafMK6XVL9SOmGieph2';
const REP = 'rep-alice';
const OTHER_REP = 'rep-bob';
const DISABLED_REP = 'rep-disabled';
const STRANGER = 'random-signed-in-user';

const GOOD_URL = 'https://www.google.com/maps/place/Rextech+Studios/@10.0,76.3,858m/data=!3m1';

let env;

before(async () => {
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  env = await initializeTestEnvironment({
    projectId: 'demo-rules',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
      host,
      port: Number(port),
    },
  });
});

after(async () => env.cleanup());

// Fresh seed data before every test.
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const shop = (name) => ({
      shopId: name,
      shopName: `Demo ${name}`,
      shopLogo: null,
      googleReviewUrl: GOOD_URL,
      createdAt: '2026-11-07T00:00:00.000Z',
      googleSheetsUrl: 'https://docs.google.com/spreadsheets/d/abc/edit',
      qrCode: 'QR1',
    });
    await setDoc(doc(db, 'shops/shopA'), shop('shopA')); // assigned to REP
    await setDoc(doc(db, 'shops/shopB'), shop('shopB')); // assigned to OTHER_REP
    await setDoc(doc(db, 'shops/shopC'), shop('shopC')); // unassigned
    await setDoc(doc(db, 'qr_codes/qrA'), { qrId: 'qrA', shopId: 'shopA', qrCode: 'QR1' });

    await setDoc(doc(db, `users/${REP}`), { uid: REP, name: 'Alice', role: 'sales', active: true });
    await setDoc(doc(db, `users/${OTHER_REP}`), { uid: OTHER_REP, name: 'Bob', role: 'sales', active: true });
    await setDoc(doc(db, `users/${DISABLED_REP}`), { uid: DISABLED_REP, name: 'Dan', role: 'sales', active: false });

    const assignment = (shopId, rep) => ({
      shopId, qrId: `qr-${shopId}`, qrCode: 'QR1', assignedTo: rep, assignedToName: 'x',
      assignedAt: new Date(), locked: false, soldAt: null, lastEditedAt: null,
    });
    await setDoc(doc(db, 'assignments/shopA'), assignment('shopA', REP));
    await setDoc(doc(db, 'assignments/shopB'), assignment('shopB', OTHER_REP));
    await setDoc(doc(db, 'assignments/shopDisabled'), { ...assignment('shopDisabled', DISABLED_REP) });
    await setDoc(doc(db, 'shops/shopDisabled'), shop('shopDisabled'));
  });
});

const anon = () => env.unauthenticatedContext().firestore();
const as = (uid) => env.authenticatedContext(uid).firestore();
const admin = () => as(ADMIN_UID);

// The exact batch the app sends when a sales person saves an edit.
function repEditBatch(db, shopId, { first = true, shopName = 'Fresh Cafe', url = GOOD_URL, extra = {} } = {}) {
  const batch = writeBatch(db);
  batch.update(doc(db, `shops/${shopId}`), { shopName, googleReviewUrl: url, ...extra });
  batch.update(doc(db, `assignments/${shopId}`), {
    locked: true,
    lastEditedAt: serverTimestamp(),
    ...(first ? { soldAt: serverTimestamp() } : {}),
  });
  return batch;
}

describe('existing behavior is unchanged', () => {
  test('anyone can get one shop', async () => {
    await assertSucceeds(getDoc(doc(anon(), 'shops/shopC')));
  });
  test('anyone cannot list shops', async () => {
    await assertFails(getDocs(collection(anon(), 'shops')));
  });
  test('anonymous cannot write or delete a shop', async () => {
    await assertFails(updateDoc(doc(anon(), 'shops/shopC'), { shopName: 'hacked' }));
    await assertFails(deleteDoc(doc(anon(), 'shops/shopC')));
  });
  test('anonymous cannot read qr_codes, feedback or unknown collections', async () => {
    await assertFails(getDocs(collection(anon(), 'qr_codes')));
    await assertFails(getDocs(collection(anon(), 'feedback')));
    await assertFails(getDoc(doc(anon(), 'anything/else')));
  });
  test('a signed-in stranger gets nothing extra', async () => {
    const db = as(STRANGER);
    await assertFails(getDocs(collection(db, 'shops')));
    await assertFails(getDocs(collection(db, 'qr_codes')));
    await assertFails(getDocs(collection(db, 'feedback')));
    await assertFails(updateDoc(doc(db, 'shops/shopC'), { shopName: 'x' }));
    await assertFails(getDocs(collection(db, 'assignments')));
    await assertFails(getDocs(collection(db, 'users')));
  });

  const feedback = (extra = {}) => ({
    shopId: 'shopC', rating: 5, createdAt: serverTimestamp(), ...extra,
  });
  test('valid anonymous feedback is accepted', async () => {
    await assertSucceeds(setDoc(doc(anon(), 'feedback/f1'), feedback()));
    await assertSucceeds(setDoc(doc(anon(), 'feedback/f2'), feedback({ comment: 'nice' })));
    await assertSucceeds(setDoc(doc(anon(), 'feedback/f3'), feedback({ comment: null })));
    await assertSucceeds(setDoc(doc(anon(), 'feedback/f4'), feedback({ emailNotificationStatus: 'pending' })));
  });
  test('invalid anonymous feedback is rejected', async () => {
    await assertFails(setDoc(doc(anon(), 'feedback/x1'), feedback({ rating: 9 })));
    await assertFails(setDoc(doc(anon(), 'feedback/x2'), feedback({ rating: 0 })));
    await assertFails(setDoc(doc(anon(), 'feedback/x3'), feedback({ rating: '5' })));
    await assertFails(setDoc(doc(anon(), 'feedback/x4'), feedback({ extra: 'x' })));
    await assertFails(setDoc(doc(anon(), 'feedback/x5'), feedback({ comment: 'x'.repeat(251) })));
    await assertFails(setDoc(doc(anon(), 'feedback/x6'), feedback({ shopId: 'no-such-shop' })));
    await assertFails(setDoc(doc(anon(), 'feedback/x7'), { shopId: 'shopC', rating: 5, createdAt: new Date('2020-01-01') }));
  });
  test('feedback cannot be updated or deleted by anonymous', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'feedback/f9'), { shopId: 'shopC', rating: 5, createdAt: new Date() }));
    await assertFails(updateDoc(doc(anon(), 'feedback/f9'), { rating: 1 }));
    await assertFails(deleteDoc(doc(anon(), 'feedback/f9')));
  });
  test('a sales person cannot read feedback or qr_codes', async () => {
    await assertFails(getDocs(collection(as(REP), 'feedback')));
    await assertFails(getDocs(collection(as(REP), 'qr_codes')));
    await assertFails(getDoc(doc(as(REP), 'qr_codes/qrA')));
  });
});

describe('admin', () => {
  test('can read and write everything', async () => {
    const db = admin();
    await assertSucceeds(getDocs(collection(db, 'shops')));
    await assertSucceeds(getDocs(collection(db, 'qr_codes')));
    await assertSucceeds(getDocs(collection(db, 'feedback')));
    await assertSucceeds(getDocs(collection(db, 'users')));
    await assertSucceeds(getDocs(collection(db, 'assignments')));
    await assertSucceeds(updateDoc(doc(db, 'shops/shopC'), { shopName: 'Edited by admin' }));
  });
  test('can create a sales user and assign a QR', async () => {
    const db = admin();
    await assertSucceeds(setDoc(doc(db, 'users/new-rep'), { uid: 'new-rep', name: 'New', role: 'sales', active: true }));
    await assertSucceeds(setDoc(doc(db, 'assignments/shopC'), {
      shopId: 'shopC', qrId: 'q', qrCode: 'QR3', assignedTo: 'new-rep', assignedToName: 'New',
      assignedAt: serverTimestamp(), locked: false, soldAt: null, lastEditedAt: null,
    }));
  });
  test('can unlock a locked assignment and disable a rep', async () => {
    const db = admin();
    await assertSucceeds(updateDoc(doc(db, 'assignments/shopA'), { locked: true }));
    await assertSucceeds(updateDoc(doc(db, 'assignments/shopA'), { locked: false }));
    await assertSucceeds(updateDoc(doc(db, `users/${REP}`), { active: false }));
  });
});

describe('admin: fixing mistakes', () => {
  test('can move an unsold assignment to another sales person', async () => {
    const db = admin();
    await assertSucceeds(updateDoc(doc(db, 'assignments/shopA'), {
      assignedTo: OTHER_REP, assignedToName: 'Bob', assignedAt: serverTimestamp(),
    }));
    // The new owner sees it; the old one no longer does.
    await assertSucceeds(getDoc(doc(as(OTHER_REP), 'assignments/shopA')));
    await assertFails(getDoc(doc(as(REP), 'assignments/shopA')));
  });

  test('can take assignments back in one batch', async () => {
    const db = admin();
    const batch = writeBatch(db);
    batch.delete(doc(db, 'assignments/shopA'));
    batch.delete(doc(db, 'assignments/shopB'));
    await assertSucceeds(batch.commit());
    await assertFails(getDoc(doc(as(REP), 'assignments/shopA')));
  });

  test('can rename a sales person and the name on their assignments', async () => {
    const db = admin();
    const batch = writeBatch(db);
    batch.update(doc(db, `users/${REP}`), { name: 'Alice Mary' });
    batch.update(doc(db, 'assignments/shopA'), { assignedToName: 'Alice Mary' });
    await assertSucceeds(batch.commit());
    const user = (await getDoc(doc(db, `users/${REP}`))).data();
    assert.equal(user.name, 'Alice Mary');
    assert.equal(user.role, 'sales');
  });

  test('deleting a sales person removes all of their access, immediately', async () => {
    const db = admin();
    // Before: they can read their own assignment and edit it.
    await assertSucceeds(getDoc(doc(as(REP), 'assignments/shopA')));

    await assertSucceeds(deleteDoc(doc(db, 'assignments/shopA')));
    await assertSucceeds(deleteDoc(doc(db, `users/${REP}`)));

    // Their login still exists in Auth, but the rules no longer know them.
    const gone = as(REP);
    await assertFails(getDocs(query(collection(gone, 'assignments'), where('assignedTo', '==', REP))));
    await assertFails(getDoc(doc(gone, 'settings/invoice')));
    await assertFails(getDoc(doc(gone, 'counters/invoices')));
    await assertFails(getDocs(query(collection(gone, 'invoices'), where('soldByUid', '==', REP))));
    await assertFails(updateDoc(doc(gone, 'shops/shopA'), {
      googleSheetsUrl: 'https://docs.google.com/spreadsheets/d/abc',
    }));
    await assertFails(getDoc(doc(gone, `users/${OTHER_REP}`)));
  });

  test('a sales person still cannot do any of these to themselves or others', async () => {
    const db = as(REP);
    await assertFails(updateDoc(doc(db, 'assignments/shopA'), { assignedTo: OTHER_REP, assignedToName: 'Bob' }));
    await assertFails(updateDoc(doc(db, 'assignments/shopB'), { assignedTo: REP, assignedToName: 'Alice' }));
    await assertFails(deleteDoc(doc(db, 'assignments/shopA')));
    await assertFails(updateDoc(doc(db, `users/${REP}`), { name: 'Hacker' }));
    await assertFails(deleteDoc(doc(db, `users/${REP}`)));
    await assertFails(deleteDoc(doc(db, `users/${OTHER_REP}`)));
  });
});

describe('sales person: accounts and visibility', () => {
  test('can read their own user doc but nobody else\'s', async () => {
    await assertSucceeds(getDoc(doc(as(REP), `users/${REP}`)));
    await assertFails(getDoc(doc(as(REP), `users/${OTHER_REP}`)));
    await assertFails(getDocs(collection(as(REP), 'users')));
  });
  test('cannot change their own role or active flag, or create users', async () => {
    const db = as(REP);
    await assertFails(updateDoc(doc(db, `users/${REP}`), { role: 'admin' }));
    await assertFails(updateDoc(doc(db, `users/${REP}`), { active: true, name: 'Boss' }));
    await assertFails(setDoc(doc(db, 'users/self-made'), { uid: 'self-made', role: 'sales', active: true }));
    await assertFails(deleteDoc(doc(db, `users/${REP}`)));
  });
  test('a stranger cannot grant themselves access', async () => {
    await assertFails(setDoc(doc(as(STRANGER), `users/${STRANGER}`), { uid: STRANGER, role: 'sales', active: true }));
    await assertFails(getDocs(query(collection(as(STRANGER), 'assignments'), where('assignedTo', '==', STRANGER))));
  });
  test('can list only their own assignments', async () => {
    const db = as(REP);
    const snap = await assertSucceeds(getDocs(query(collection(db, 'assignments'), where('assignedTo', '==', REP))));
    if (snap.size !== 1) throw new Error(`expected 1 own assignment, got ${snap.size}`);
    await assertFails(getDocs(collection(db, 'assignments')));
    await assertFails(getDocs(query(collection(db, 'assignments'), where('assignedTo', '==', OTHER_REP))));
  });
  test('can get their own assignment but not another rep\'s', async () => {
    await assertSucceeds(getDoc(doc(as(REP), 'assignments/shopA')));
    await assertFails(getDoc(doc(as(REP), 'assignments/shopB')));
  });
  test('cannot create or delete assignments', async () => {
    const db = as(REP);
    await assertFails(setDoc(doc(db, 'assignments/shopC'), {
      shopId: 'shopC', assignedTo: REP, locked: false, soldAt: null, lastEditedAt: null,
    }));
    await assertFails(deleteDoc(doc(db, 'assignments/shopA')));
  });
  test('cannot list shops, and cannot touch shops that are not theirs', async () => {
    const db = as(REP);
    await assertFails(getDocs(collection(db, 'shops')));
    await assertFails(repEditBatch(db, 'shopB').commit());
    await assertFails(repEditBatch(db, 'shopC').commit());
  });
});

describe('sales person: editing an assigned QR', () => {
  test('can edit once: shop changes and the assignment locks with a server soldAt', async () => {
    const db = as(REP);
    await assertSucceeds(repEditBatch(db, 'shopA').commit());
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const shop = (await getDoc(doc(db, 'shops/shopA'))).data();
      const asg = (await getDoc(doc(db, 'assignments/shopA'))).data();
      if (shop.shopName !== 'Fresh Cafe') throw new Error('shop name not saved');
      if (asg.locked !== true) throw new Error('assignment not locked');
      if (!asg.soldAt) throw new Error('soldAt not set');
    });
  });
  test('a second edit is refused while locked', async () => {
    const db = as(REP);
    await assertSucceeds(repEditBatch(db, 'shopA').commit());
    await assertFails(repEditBatch(db, 'shopA', { first: false, shopName: 'Sneaky' }).commit());
  });
  test('after the admin unlocks, they can edit again without changing soldAt', async () => {
    const db = as(REP);
    await assertSucceeds(repEditBatch(db, 'shopA').commit());
    await assertSucceeds(updateDoc(doc(admin(), 'assignments/shopA'), { locked: false }));
    await assertSucceeds(repEditBatch(db, 'shopA', { first: false, shopName: 'Second edit' }).commit());
  });
  test('cannot rewrite soldAt on a later edit', async () => {
    const db = as(REP);
    await assertSucceeds(repEditBatch(db, 'shopA').commit());
    await assertSucceeds(updateDoc(doc(admin(), 'assignments/shopA'), { locked: false }));
    await assertFails(repEditBatch(db, 'shopA', { first: true }).commit());
  });
  test('cannot edit the shop without locking the assignment in the same batch', async () => {
    const db = as(REP);
    await assertFails(updateDoc(doc(db, 'shops/shopA'), { shopName: 'No lock', googleReviewUrl: GOOD_URL }));
  });
  test('cannot lock with a client-chosen date', async () => {
    const db = as(REP);
    const batch = writeBatch(db);
    batch.update(doc(db, 'shops/shopA'), { shopName: 'Backdated' });
    batch.update(doc(db, 'assignments/shopA'), {
      locked: true, lastEditedAt: serverTimestamp(), soldAt: new Date('2020-01-01'),
    });
    await assertFails(batch.commit());
  });
  test('cannot change fields other than shopName and googleReviewUrl', async () => {
    const db = as(REP);
    await assertFails(repEditBatch(db, 'shopA', { extra: { googleSheetsUrl: 'https://evil.example/' } }).commit());
    await assertFails(repEditBatch(db, 'shopA', { extra: { qrCode: 'QR999' } }).commit());
    await assertFails(repEditBatch(db, 'shopA', { extra: { shopLogo: 'x' } }).commit());
  });
  test('cannot change assignedTo, shopId or other assignment fields', async () => {
    const db = as(REP);
    const batch = writeBatch(db);
    batch.update(doc(db, 'shops/shopA'), { shopName: 'Steal' });
    batch.update(doc(db, 'assignments/shopA'), {
      locked: true, lastEditedAt: serverTimestamp(), soldAt: serverTimestamp(), assignedTo: OTHER_REP,
    });
    await assertFails(batch.commit());
  });
  test('cannot unlock an assignment', async () => {
    const db = as(REP);
    await assertSucceeds(repEditBatch(db, 'shopA').commit());
    await assertFails(updateDoc(doc(db, 'assignments/shopA'), { locked: false }));
  });
  test('rejects unsafe or malformed review links', async () => {
    const db = as(REP);
    for (const url of [
      'http://www.google.com/maps/place/x',
      'https://evil.example/maps',
      'https://google.com.evil.example/x',
      'https://evil.example/google.com',
      'https://google.com@evil.example/x',
      'javascript:alert(1)',
      'https://www.google.com/a b',
      '',
      'https://www.google.com/' + 'x'.repeat(2000),
    ]) {
      await assertFails(repEditBatch(db, 'shopA', { url }).commit());
    }
  });
  test('accepts the normal kinds of Google review links', async () => {
    for (const url of [
      'https://g.page/r/CabcDEF/review',
      'https://maps.app.goo.gl/AbCdEf123',
      'https://www.google.com/maps/place/Foo',
      'https://search.google.com/local/writereview?placeid=ChIJ123',
      'https://maps.google.com/?cid=123',
    ]) {
      await env.clearFirestore();
      await env.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, 'shops/shopA'), { shopId: 'shopA', shopName: 'Demo', googleReviewUrl: GOOD_URL });
        await setDoc(doc(db, `users/${REP}`), { uid: REP, name: 'A', role: 'sales', active: true });
        await setDoc(doc(db, 'assignments/shopA'), {
          shopId: 'shopA', assignedTo: REP, locked: false, soldAt: null, lastEditedAt: null,
        });
      });
      await assertSucceeds(repEditBatch(as(REP), 'shopA', { url }).commit());
    }
  });
  test('rejects an empty or oversized shop name', async () => {
    const db = as(REP);
    await assertFails(repEditBatch(db, 'shopA', { shopName: '' }).commit());
    await assertFails(repEditBatch(db, 'shopA', { shopName: 'x'.repeat(101) }).commit());
  });
  test('cannot delete a shop or create one', async () => {
    const db = as(REP);
    await assertFails(deleteDoc(doc(db, 'shops/shopA')));
    await assertFails(setDoc(doc(db, 'shops/brandNew'), { shopId: 'brandNew', shopName: 'x', googleReviewUrl: GOOD_URL }));
  });
});

describe('sales person: attaching a Google Sheet', () => {
  const SHEET = 'https://docs.google.com/spreadsheets/d/1AbC-dEf_123/edit';

  // shopA is Alice's. Give it no sheet, as a demo QR whose sheet was never made.
  async function withoutSheet(shopId = 'shopA', how = 'missing') {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const ref = doc(ctx.firestore(), `shops/${shopId}`);
      const data = (await getDoc(ref)).data();
      delete data.googleSheetsUrl;
      if (how === 'null') data.googleSheetsUrl = null;
      if (how === 'empty') data.googleSheetsUrl = '';
      await setDoc(ref, data);
    });
  }

  test('can add one to their own shop that has none (field missing, null or empty)', async () => {
    for (const how of ['missing', 'null', 'empty']) {
      await withoutSheet('shopA', how);
      await assertSucceeds(updateDoc(doc(as(REP), 'shops/shopA'), { googleSheetsUrl: SHEET }));
    }
  });

  test('can add one while the QR is locked or unlocked, without touching anything else', async () => {
    await withoutSheet();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'assignments/shopA'), { locked: true, soldAt: new Date() });
    });
    await assertSucceeds(updateDoc(doc(as(REP), 'shops/shopA'), { googleSheetsUrl: SHEET }));
    const shop = (await getDoc(doc(admin(), 'shops/shopA'))).data();
    assert.equal(shop.shopName, 'Demo shopA');
    assert.equal(shop.googleReviewUrl, GOOD_URL);
  });

  test('cannot replace a sheet the shop already has', async () => {
    // The seed gives shopA a sheet already.
    await assertFails(updateDoc(doc(as(REP), 'shops/shopA'), { googleSheetsUrl: SHEET }));
  });

  test("cannot add one to someone else's shop or an unassigned shop", async () => {
    await withoutSheet('shopB');
    await withoutSheet('shopC');
    await assertFails(updateDoc(doc(as(REP), 'shops/shopB'), { googleSheetsUrl: SHEET }));
    await assertFails(updateDoc(doc(as(REP), 'shops/shopC'), { googleSheetsUrl: SHEET }));
  });

  test('refuses anything that is not a Google Sheets link', async () => {
    await withoutSheet();
    const bad = [
      'http://docs.google.com/spreadsheets/d/abc',
      'https://evil.example/spreadsheets/d/abc',
      'https://docs.google.com.evil.example/spreadsheets/d/abc',
      'https://docs.google.com/document/d/abc',
      'https://docs.google.com/spreadsheets/d/',
      'https://docs.google.com/spreadsheets/d/abc def',
      'javascript:alert(1)',
      `https://docs.google.com/spreadsheets/d/${'a'.repeat(300)}`,
      '',
      12345,
      null,
    ];
    for (const url of bad) {
      await assertFails(updateDoc(doc(as(REP), 'shops/shopA'), { googleSheetsUrl: url }));
    }
  });

  test('cannot change other fields in the same write', async () => {
    await withoutSheet();
    await assertFails(updateDoc(doc(as(REP), 'shops/shopA'), { googleSheetsUrl: SHEET, shopName: 'Sneaky' }));
    await assertFails(updateDoc(doc(as(REP), 'shops/shopA'), { googleSheetsUrl: SHEET, googleReviewUrl: GOOD_URL + '?x=1' }));
    await assertFails(updateDoc(doc(as(REP), 'shops/shopA'), { googleSheetsUrl: SHEET, qrCode: 'QR999' }));
  });

  test('a disabled sales person, a stranger and a visitor cannot', async () => {
    await withoutSheet('shopDisabled');
    await withoutSheet();
    await assertFails(updateDoc(doc(as(DISABLED_REP), 'shops/shopDisabled'), { googleSheetsUrl: SHEET }));
    await assertFails(updateDoc(doc(as(STRANGER), 'shops/shopA'), { googleSheetsUrl: SHEET }));
    await assertFails(updateDoc(doc(anon(), 'shops/shopA'), { googleSheetsUrl: SHEET }));
  });

  test('the admin can still set or replace any sheet', async () => {
    await assertSucceeds(updateDoc(doc(admin(), 'shops/shopA'), { googleSheetsUrl: SHEET }));
  });
});

describe('disabled sales person', () => {
  test('loses all access', async () => {
    const db = as(DISABLED_REP);
    await assertFails(getDocs(query(collection(db, 'assignments'), where('assignedTo', '==', DISABLED_REP))));
    await assertFails(getDoc(doc(db, 'assignments/shopDisabled')));
    await assertFails(repEditBatch(db, 'shopDisabled').commit());
  });
  test('can still read their own user doc so the app can say why', async () => {
    await assertSucceeds(getDoc(doc(as(DISABLED_REP), `users/${DISABLED_REP}`)));
  });
  test('an admin re-enabling them restores access', async () => {
    await assertSucceeds(updateDoc(doc(admin(), `users/${DISABLED_REP}`), { active: true }));
    await assertSucceeds(getDoc(doc(as(DISABLED_REP), 'assignments/shopDisabled')));
  });
});

describe('invoices', () => {
  // QR1 on shopA is Alice's and has been set up (sold) at SOLD_AT.
  const SOLD_AT = Timestamp.fromMillis(1762700000000);

  const invoiceFor = (shopId, rep, name, over = {}) => ({
    shopId, number: 1, qrCode: 'QR1', clientName: 'Sunrise Bakery',
    clientPhone: '98765 43210', clientAddress: 'MG Road, Kochi', amount: 1500,
    issuedAt: serverTimestamp(), soldAt: SOLD_AT, soldByName: name,
    soldByUid: rep, createdByUid: rep, createdByName: name, ...over,
  });

  // What the app sends: the invoice and the counter bump in one commit.
  function invoiceBatch(db, shopId, invoice, counter = {}) {
    const batch = writeBatch(db);
    batch.set(doc(db, 'counters/invoices'), {
      last: invoice.number, lastShopId: shopId, ...counter,
    });
    batch.set(doc(db, `invoices/${shopId}`), invoice);
    return batch;
  }

  async function seed({ price = 1500, counter = null, extraSold = [] } = {}) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const s = ctx.firestore();
      await updateDoc(doc(s, 'assignments/shopA'), {
        soldAt: SOLD_AT, locked: true, assignedToName: 'Alice',
      });
      await updateDoc(doc(s, 'assignments/shopB'), {
        soldAt: SOLD_AT, locked: true, assignedToName: 'Bob',
      });
      for (const [shopId, rep, name] of extraSold) {
        await setDoc(doc(s, `assignments/${shopId}`), {
          shopId, qrId: `qr-${shopId}`, qrCode: 'QR1', assignedTo: rep, assignedToName: name,
          assignedAt: new Date(), locked: true, soldAt: SOLD_AT, lastEditedAt: SOLD_AT,
        });
      }
      if (price !== null) await setDoc(doc(s, 'settings/invoice'), { pricePerQr: price });
      if (counter) await setDoc(doc(s, 'counters/invoices'), counter);
    });
  }

  describe('the admin', () => {
    test('can issue an invoice, take a number and set the price', async () => {
      const db = admin();
      await assertSucceeds(setDoc(doc(db, 'counters/invoices'), { last: 1, lastShopId: 'shopA' }));
      await assertSucceeds(setDoc(doc(db, 'invoices/shopA'), invoiceFor('shopA', REP, 'Alice', { createdByUid: ADMIN_UID })));
      await assertSucceeds(setDoc(doc(db, 'settings/invoice'), { pricePerQr: 1800 }));
      await assertSucceeds(getDoc(doc(db, 'invoices/shopA')));
      await assertSucceeds(getDocs(collection(db, 'invoices')));
    });
  });

  describe('a sales person making their own invoice', () => {
    test('works for their own set-up QR at the admin price, the very first invoice included', async () => {
      await seed();
      const db = as(REP);
      await assertSucceeds(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice')).commit());
    });

    test('works through a real transaction like the app uses', async () => {
      await seed();
      const db = as(REP);
      await assertSucceeds(runTransaction(db, async (tx) => {
        const invRef = doc(db, 'invoices/shopA');
        const existing = await tx.get(invRef); // no invoice yet: must be readable
        assert.equal(existing.exists(), false);
        const asg = await tx.get(doc(db, 'assignments/shopA'));
        const counter = await tx.get(doc(db, 'counters/invoices'));
        const next = (counter.exists() ? counter.data().last : 0) + 1;
        tx.set(doc(db, 'counters/invoices'), { last: next, lastShopId: 'shopA' });
        tx.set(invRef, invoiceFor('shopA', REP, 'Alice', {
          number: next, soldAt: asg.data().soldAt, qrCode: asg.data().qrCode,
          soldByName: asg.data().assignedToName,
        }));
      }));
      const saved = await assertSucceeds(getDoc(doc(as(REP), 'invoices/shopA')));
      assert.equal(saved.data().number, 1);
    });

    test('the next number must follow on from the counter', async () => {
      await seed({ counter: { last: 4, lastShopId: 'earlier' }, extraSold: [['shopA2', REP, 'Alice']] });
      const db = as(REP);
      await assertSucceeds(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice', { number: 5 })).commit());
      await assertSucceeds(invoiceBatch(db, 'shopA2', invoiceFor('shopA2', REP, 'Alice', { number: 6 })).commit());
    });

    test('can read their own invoice and list their own, but only with their own filter', async () => {
      await seed({ counter: { last: 1, lastShopId: 'shopB' } });
      await env.withSecurityRulesDisabled(async (ctx) => {
        const s = ctx.firestore();
        await setDoc(doc(s, 'invoices/shopA'), invoiceFor('shopA', REP, 'Alice', { number: 2 }));
        await setDoc(doc(s, 'invoices/shopB'), invoiceFor('shopB', OTHER_REP, 'Bob', { number: 1 }));
      });
      const db = as(REP);
      await assertSucceeds(getDoc(doc(db, 'invoices/shopA')));
      const mine = await assertSucceeds(getDocs(query(collection(db, 'invoices'), where('soldByUid', '==', REP))));
      assert.deepEqual(mine.docs.map((d) => d.id), ['shopA']);

      await assertFails(getDoc(doc(db, 'invoices/shopB')));
      await assertFails(getDocs(collection(db, 'invoices')));
      await assertFails(getDocs(query(collection(db, 'invoices'), where('soldByUid', '==', OTHER_REP))));
    });

    test('is cleanly refused (not an error) on an old invoice that has no soldByUid', async () => {
      await seed({ counter: { last: 1, lastShopId: 'shopA' } });
      await env.withSecurityRulesDisabled(async (ctx) => {
        const old = invoiceFor('shopA', REP, 'Alice', { issuedAt: new Date() });
        delete old.soldByUid;
        delete old.createdByUid;
        delete old.createdByName;
        await setDoc(doc(ctx.firestore(), 'invoices/shopA'), old);
      });
      await assertFails(getDoc(doc(as(REP), 'invoices/shopA')));
      await assertSucceeds(getDoc(doc(admin(), 'invoices/shopA')));
      const mine = await assertSucceeds(
        getDocs(query(collection(as(REP), 'invoices'), where('soldByUid', '==', REP))),
      );
      assert.equal(mine.size, 0);
    });

    test('can read the fixed price and the counter, but not change either', async () => {
      await seed({ counter: { last: 3, lastShopId: 'x' } });
      const db = as(REP);
      await assertSucceeds(getDoc(doc(db, 'settings/invoice')));
      await assertSucceeds(getDoc(doc(db, 'counters/invoices')));
      await assertFails(setDoc(doc(db, 'settings/invoice'), { pricePerQr: 1 }));
      await assertFails(updateDoc(doc(db, 'settings/invoice'), { pricePerQr: 1 }));
      await assertFails(setDoc(doc(db, 'counters/invoices'), { last: 0, lastShopId: 'x' }));
      await assertFails(deleteDoc(doc(db, 'counters/invoices')));
    });

    test('cannot reach any other setting or counter', async () => {
      await seed();
      await env.withSecurityRulesDisabled(async (ctx) => {
        const s = ctx.firestore();
        await setDoc(doc(s, 'settings/other'), { secret: 1 });
        await setDoc(doc(s, 'counters/other'), { last: 1 });
      });
      const db = as(REP);
      await assertFails(getDoc(doc(db, 'settings/other')));
      await assertFails(getDoc(doc(db, 'counters/other')));
      await assertFails(setDoc(doc(db, 'counters/other'), { last: 2 }));
    });
  });

  describe('what a sales person cannot do', () => {
    test('invoice a QR that is not set up yet', async () => {
      await seed();
      await env.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), 'assignments/shopA'), { soldAt: null, locked: false });
      });
      await assertFails(invoiceBatch(as(REP), 'shopA', invoiceFor('shopA', REP, 'Alice')).commit());
    });

    test("invoice someone else's QR, or one that is unassigned", async () => {
      await seed();
      const db = as(REP);
      await assertFails(invoiceBatch(db, 'shopB', invoiceFor('shopB', REP, 'Bob')).commit());
      await assertFails(invoiceBatch(db, 'shopB', invoiceFor('shopB', OTHER_REP, 'Bob')).commit());
      await assertFails(invoiceBatch(db, 'shopC', invoiceFor('shopC', REP, 'Alice')).commit());
    });

    test('pick their own price', async () => {
      await seed();
      const db = as(REP);
      await assertFails(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice', { amount: 1 })).commit());
      await assertFails(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice', { amount: 1499 })).commit());
      await assertFails(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice', { amount: '1500' })).commit());
      await assertFails(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice', { amount: 1500.5 })).commit());
    });

    test('invoice anything while the admin has set no price', async () => {
      await seed({ price: null });
      await assertFails(invoiceBatch(as(REP), 'shopA', invoiceFor('shopA', REP, 'Alice')).commit());
    });

    test('skip, repeat or go back on invoice numbers', async () => {
      await seed({ counter: { last: 4, lastShopId: 'earlier' } });
      const db = as(REP);
      await assertFails(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice', { number: 6 })).commit());
      await assertFails(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice', { number: 4 })).commit());
      await assertFails(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice', { number: 1 })).commit());
      // The invoice says 5 but the counter says 7.
      await assertFails(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice', { number: 5 }), { last: 7 }).commit());
    });

    test('use up a number without making an invoice', async () => {
      await seed({ counter: { last: 4, lastShopId: 'earlier' } });
      const db = as(REP);
      await assertFails(setDoc(doc(db, 'counters/invoices'), { last: 5, lastShopId: 'shopA' }));
      await assertFails(setDoc(doc(db, 'counters/invoices'), { last: 5, lastShopId: 'shopB' }));
      // Pointing the counter at a shop that already has an invoice does not count.
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'invoices/shopB'), invoiceFor('shopB', OTHER_REP, 'Bob', { number: 3 }));
      });
      await assertFails(setDoc(doc(db, 'counters/invoices'), { last: 5, lastShopId: 'shopB' }));
    });

    test('start the counter anywhere but 1', async () => {
      await seed();
      await assertFails(invoiceBatch(as(REP), 'shopA', invoiceFor('shopA', REP, 'Alice', { number: 50 })).commit());
    });

    test('invoice the same QR twice, or change or delete an invoice', async () => {
      await seed({ counter: { last: 1, lastShopId: 'shopA' } });
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'invoices/shopA'), invoiceFor('shopA', REP, 'Alice', { issuedAt: new Date() }));
      });
      const db = as(REP);
      await assertFails(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice', { number: 2 })).commit());
      await assertFails(updateDoc(doc(db, 'invoices/shopA'), { amount: 1 }));
      await assertFails(updateDoc(doc(db, 'invoices/shopA'), { clientName: 'Someone Else' }));
      await assertFails(deleteDoc(doc(db, 'invoices/shopA')));
    });

    test('put anything but the true facts on an invoice', async () => {
      await seed();
      const db = as(REP);
      const bad = [
        { soldByUid: OTHER_REP },
        { createdByUid: OTHER_REP },
        { createdByUid: ADMIN_UID },
        { soldByName: 'Bob' },
        { qrCode: 'QR999' },
        { shopId: 'shopB' },
        { soldAt: Timestamp.fromMillis(1) },
        { issuedAt: new Date(2020, 1, 1) },
        { clientName: '' },
        { clientName: 'x'.repeat(101) },
        { clientName: 7 },
        { clientPhone: '1'.repeat(21) },
        { clientAddress: 'x'.repeat(201) },
        { createdByName: 'x'.repeat(101) },
        { extraField: 'sneaky' },
      ];
      for (const over of bad) {
        await assertFails(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice', over)).commit());
      }
    });

    test('leave out a field', async () => {
      await seed();
      for (const field of ['clientPhone', 'clientAddress', 'createdByUid', 'soldByUid', 'soldAt', 'amount']) {
        const invoice = invoiceFor('shopA', REP, 'Alice');
        delete invoice[field];
        await assertFails(invoiceBatch(as(REP), 'shopA', invoice).commit());
      }
    });

    test('invoice while their account is turned off', async () => {
      await seed({ extraSold: [['shopDisabled', DISABLED_REP, 'Dan']] });
      await assertFails(invoiceBatch(as(DISABLED_REP), 'shopDisabled', invoiceFor('shopDisabled', DISABLED_REP, 'Dan')).commit());
      await assertFails(getDoc(doc(as(DISABLED_REP), 'settings/invoice')));
    });
  });

  describe('everyone else', () => {
    test('another signed-in user and a visitor get nothing', async () => {
      await seed({ counter: { last: 1, lastShopId: 'shopA' } });
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'invoices/shopA'), invoiceFor('shopA', REP, 'Alice', { issuedAt: new Date() }));
      });
      for (const db of [as(STRANGER), env.unauthenticatedContext().firestore()]) {
        await assertFails(getDoc(doc(db, 'invoices/shopA')));
        await assertFails(getDocs(collection(db, 'invoices')));
        await assertFails(getDocs(query(collection(db, 'invoices'), where('soldByUid', '==', REP))));
        await assertFails(getDoc(doc(db, 'settings/invoice')));
        await assertFails(getDoc(doc(db, 'counters/invoices')));
        await assertFails(invoiceBatch(db, 'shopA', invoiceFor('shopA', REP, 'Alice')).commit());
        await assertFails(setDoc(doc(db, 'counters/invoices'), { last: 99, lastShopId: 'shopA' }));
      }
    });
  });
});
