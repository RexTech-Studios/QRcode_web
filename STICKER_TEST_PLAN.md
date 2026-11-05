# Sticker test plan (phase 1b)

Printed stickers encode `https://qrcode-16b68.web.app/#/review/<shopId>`. This file records what was tested locally and lists what only you can test.

All 41 shop ids in the database pass the shim's pattern, and all 24 stored QR codes use that exact URL form.

## How the local tests ran

Everything ran against the real `dist/` in Chrome, with pages loaded only: no login, no review submitted, no Firestore writes. Test shop: Rextech Studios (`035084ec-5bd9-4b1f-b325-9684aa2dc602`).

- **Browser tests** used the Firebase hosting emulator.
- **Header and redirect tests could not use the emulator.** On Windows it ignores every configured header and redirect, because `glob-slasher` turns `/app` into `\app`, which never matches a URL. They ran on the same `superstatic` server with that one bug worked around outside the repo. This checks the patterns in `firebase.json`, but it is not Firebase's production server.

## Results

| Test | Result |
|---|---|
| (a) `/#/review/<id>` | Pass. Ends at `/app/#/review/<id>`, the form renders, and the only request before the redirect is `/` itself (3 of 3 runs) |
| (b) `/r/<id>` | Pass. Same result. `/r/short` and `/r/a/b/c` go to `/` |
| (c) `/` | Pass. Landing page shown, one host contacted, favicon links present |
| (d) `/app/` | Pass. Login renders, gold-star favicon link, no Firestore requests while signed out |
| (e) `/app/anything`, `/anything` | Pass. App, and a 404 with `404.html` |
| (f) `/flutter_service_worker.js` | Pass. It is the kill-switch, with `no-cache` |
| (g) Headers | Pass, on the workaround server |
| (h) `/app` to `/app/` | Pass, on the workaround server: one 301, then 200 |
| (i) Screenshots | See below |
| (j) Lighthouse | Performance 97, accessibility 95, SEO 100. 96 KiB transferred for `/` |

Also checked: in-page anchors never redirect, the mobile menu opens and closes (button, Escape, link click), the page works with JavaScript off, and 53 Node tests pass against the shipped scripts.

### Kill-switch

Tested with a simulated cache-first root worker, then the site swapped for `dist/` on the same origin.

| Scenario | Result |
|---|---|
| Visitor at `/` | Old worker replaced, caches deleted, worker unregistered, landing page shown |
| The same, with no forced update | Worked on a normal visit |
| Fresh sticker tab under the old worker | Page reloads and the shim sends it to the review form |
| Tab where the hash was changed after loading | Lands on `/`, because the hash isn't part of the worker's view of that tab. A scan never does this |

Flutter's own worker in this SDK removes itself, and the live site's root worker is the same stub, so real browsers are unlikely to be holding an old app. Under `/app/`, Flutter made no `register` call at all.

### Screenshots

Saved in `design-reference/out/`. The references were each resized separately, so each was compared at its own calibrated width (about 1528-1535 px). There are no references for 1600, 1280, 768 or 390 px, so those widths were checked by eye against the guide.

Everything measured within about 3 px of the references, except:

- "THANK YOU FOR YOUR TIME!" is about 11 px wider, because the reference falls back to Roboto.
- Step 3 wraps differently, because of the `CLAIM_PRIVATE_FEEDBACK` wording.

## What couldn't be verified locally

- Whether production Hosting treats `/app/` and `/app` the way the local server does. Step 3 of `DEPLOY_PHASE_1B.md` checks this before anything goes live.
- Production header behaviour and default cache lifetimes.
- A real old browser's update timing. Chrome re-checks a worker lazily, so a returning visitor may see the old page once.

## Manual tests for you

### Real sticker, on a phone

- [ ] Scan a real printed sticker on the live site. It opens `qrcode-16b68.web.app` and ends on the review form for that shop.
- [ ] Open `https://fullstarqr.com/#/review/<id>` on the same phone. It ends on the same form.
- [ ] Open `https://fullstarqr.com/r/<id>`. It ends on the same form.
- [ ] Submit one 1-3 star review and one 4-5 star review with your own shop. The row reaches the sheet, and Google opens.
- [ ] Repeat the scan on both iPhone Safari and Android Chrome if you have them.

### Your main Chrome profile, with the old app cached

- [ ] Before deploying, open DevTools > Application > Service Workers on `qrcode-16b68.web.app` and note whether anything is registered.
- [ ] After deploying, visit `/`. You should get the landing page, at worst after one reload.
- [ ] Open `/#/review/<id>`. It ends at `/app/#/review/<id>`.
- [ ] DevTools > Application > Service Workers shows nothing left at the root scope.
- [ ] Open `/app/`. You are still logged in, or can log in.

### Domains

- [ ] Log in at both `fullstarqr.com/app/` and `qrcode-16b68.web.app/app/`. Each hostname keeps its own login and cache.
