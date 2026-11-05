// Runs the inline redirect scripts exactly as shipped, pulled out of the HTML.
// Run from the repo root:  node --test "tools/test/*.test.mjs"
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const UUID = '035084ec-5bd9-4b1f-b325-9684aa2dc602';

function firstScript(path) {
  const html = readFileSync(path, 'utf8');
  return { html, code: /<script>([\s\S]*?)<\/script>/.exec(html)[1] };
}

function run(code, location) {
  const calls = [];
  const written = [];
  vm.runInNewContext(code, {
    location: { ...location, replace: (url) => calls.push(url) },
    document: { write: (text) => written.push(text) },
  });
  return { calls, written };
}

const shim = firstScript('landing/index.html');
const shortLink = firstScript('landing/r/index.html');

const redirects = (hash) => run(shim.code, { hash }).calls;

test('shim comes first: only charset and viewport may precede it', () => {
  const head = shim.html.slice(shim.html.indexOf('<head>') + 6, shim.html.indexOf('<script>'));
  const tags = head.match(/<[a-z]+[^>]*>/gi) ?? [];
  assert.equal(tags.length, 2);
  assert.match(tags[0], /charset/i);
  assert.match(tags[1], /viewport/i);
});

test('shim redirects a valid UUID, keeping the hash', () => {
  assert.deepEqual(redirects(`#/review/${UUID}`), [`/app/#/review/${UUID}`]);
});

test('shim stops the parser after redirecting', () => {
  const { written } = run(shim.code, { hash: `#/review/${UUID}` });
  assert.equal(written.length, 1);
  assert.match(written[0], /^<plaintext/);
});

test('shim leaves the parser alone when it does not redirect', () => {
  assert.deepEqual(run(shim.code, { hash: '#features' }).written, []);
});

test('shim allows a trailing slash', () => {
  assert.deepEqual(redirects(`#/review/${UUID}/`), [`/app/#/review/${UUID}/`]);
});

test('shim allows uppercase ids', () => {
  const id = UUID.toUpperCase();
  assert.deepEqual(redirects(`#/review/${id}`), [`/app/#/review/${id}`]);
});

test('shim accepts the shortest and longest ids', () => {
  assert.equal(redirects(`#/review/${'a'.repeat(8)}`).length, 1);
  assert.equal(redirects(`#/review/${'a'.repeat(64)}`).length, 1);
});

for (const [name, hash] of [
  ['empty hash', ''],
  ['a bare hash', '#'],
  ['no id', '#/review/'],
  ['no id or slash', '#/review'],
  ['path traversal', '#/review/../x'],
  ['deep traversal', '#/review/../../etc/passwd'],
  ['a protocol-relative host', '#//evil.com'],
  ['an embedded host', `#/review/${UUID}//evil.com`],
  ['a javascript: string', '#javascript:alert(1)'],
  ['a javascript: id', '#/review/javascript:alert(1)'],
  ['another route', '#/other'],
  ['the root route', '#/'],
  ['an in-page anchor: home', '#home'],
  ['an in-page anchor: features', '#features'],
  ['an in-page anchor: about', '#about'],
  ['an in-page anchor: contact', '#contact'],
  ['an id that is too short', `#/review/${'a'.repeat(7)}`],
  ['an id that is too long', `#/review/${'a'.repeat(65)}`],
  ['an id with spaces', '#/review/abc def ghi'],
  ['an id with encoded spaces', '#/review/abc%20def%20ghi'],
  ['encoded slashes', '#/review/abcdefgh%2Fevil'],
  ['a second path segment', `#/review/${UUID}/extra`],
  ['two trailing slashes', `#/review/${UUID}//`],
  ['a query string', `#/review/${UUID}?x=1`],
  ['an uppercase route', `#/REVIEW/${UUID}`],
  ['a newline after the id', `#/review/${UUID}\n`],
]) {
  test(`shim ignores ${name}`, () => assert.deepEqual(redirects(hash), []));
}

const opened = (pathname) => run(shortLink.code, { pathname }).calls;

test('short link opens a valid id in the app', () => {
  assert.deepEqual(opened(`/r/${UUID}`), [`/app/#/review/${UUID}`]);
});

test('short link allows a trailing slash', () => {
  assert.deepEqual(opened(`/r/${UUID}/`), [`/app/#/review/${UUID}`]);
});

for (const [name, pathname] of [
  ['no id', '/r/'],
  ['no slash', '/r'],
  ['a short id', '/r/abc'],
  ['a long id', `/r/${'a'.repeat(65)}`],
  ['traversal', '/r/../x'],
  ['an encoded slash', '/r/abcdefgh%2Fevil'],
  ['an extra segment', `/r/${UUID}/extra`],
  ['a host-like path', '/r//evil.com'],
  ['a different prefix', `/x/r/${UUID}`],
]) {
  test(`short link sends ${name} to the home page`, () => {
    assert.deepEqual(opened(pathname), ['/']);
  });
}
