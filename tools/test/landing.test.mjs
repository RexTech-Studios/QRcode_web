// Static checks on the landing page. Run with:  node --test "tools/test/*.test.mjs"
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const html = readFileSync('landing/index.html', 'utf8');
const body = html.slice(html.lastIndexOf('<body>'));

const configCode = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)][1][1];
const config = vm.runInNewContext(`${configCode}
  ({ CONTACT_PHONE, CONTACT_EMAIL, CONTACT_LOCATION, WHATSAPP_URL, COPY,
     SHOW_LEGAL_LINKS, SHOW_SOCIAL_LINKS, LEGAL_LINKS, SOCIAL_LINKS, CLAIM_PRIVATE_FEEDBACK })`);

test('static markup matches the config block', () => {
  assert.ok(body.includes(`>${config.CONTACT_PHONE}<`));
  assert.ok(body.includes(`href="tel:${config.CONTACT_PHONE.replace(/\s/g, '')}"`));
  assert.ok(body.includes(`>${config.CONTACT_EMAIL}<`));
  assert.ok(body.includes(`href="mailto:${config.CONTACT_EMAIL}"`));
  assert.ok(body.includes(`>${config.CONTACT_LOCATION}<`));
  assert.ok(body.includes(`>${config.COPY.shareStep}<`));
  assert.ok(body.includes(`>${config.COPY.phoneSecondaryButton}<`));
  const whatsapp = [...body.matchAll(/href="(https:\/\/wa\.me[^"]*)"/g)].map((m) => m[1]);
  assert.equal(whatsapp.length, 4);
  assert.ok(whatsapp.every((url) => url === config.WHATSAPP_URL));
});

test('the private-feedback claim is off, and its wording is kept behind the flag', () => {
  assert.equal(config.CLAIM_PRIVATE_FEEDBACK, false);
  assert.ok(!body.toLowerCase().includes('private feedback'));
  assert.ok(html.includes('They can post a Google review or send private feedback.'));
  assert.ok(html.includes("'Send Private Feedback'"));
});

test('legal and social links are off and have no placeholder URLs', () => {
  assert.equal(config.SHOW_LEGAL_LINKS, false);
  assert.equal(config.SHOW_SOCIAL_LINKS, false);
  for (const link of [...config.LEGAL_LINKS, ...config.SOCIAL_LINKS]) assert.equal(link.url, '');
  assert.ok(!body.includes('Privacy Policy'));
});

test('exactly one h1, and the required section ids exist', () => {
  assert.equal(body.match(/<h1[\s>]/g).length, 1);
  for (const id of ['home', 'features', 'about', 'contact']) {
    assert.ok(body.includes(`id="${id}"`), id);
  }
});

test('every image has alt text and explicit dimensions', () => {
  for (const [img] of body.matchAll(/<img[^>]*>/g)) {
    assert.match(img, /alt="[^"]+"/);
    assert.match(img, /width="\d+"/);
    assert.match(img, /height="\d+"/);
  }
});

test('only the two critical fonts are preloaded', () => {
  assert.equal(html.match(/rel="preload"/g).length, 2);
});

test('there is no visible link to the app', () => {
  assert.ok(!/href="\/app[/"]/.test(body));
});

test('every external URL is an allowed host', () => {
  for (const [url] of html.matchAll(/https?:\/\/[^\s"'`)<]+/g)) {
    assert.match(url, /^https:\/\/(fullstarqr\.com|wa\.me)(\/|$)/, url);
  }
});
