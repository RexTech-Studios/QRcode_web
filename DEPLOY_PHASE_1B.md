# Deploying phase 1b

Follow these steps in order, from the `phase-1b-landing-and-domain` branch, in PowerShell. Don't run the build from Git Bash: it rewrites `--base-href /app/` into a Windows path and the build fails.

The Firebase project serves `fullstarqr.com` and `qrcode-16b68.web.app` from one site, so each deploy appears on both.

## Steps

### 1. Build for preview

```powershell
.\deploy.ps1 -Preview
```

If the build crashes with an out-of-memory style error, close any running `flutter run` session and try again.

### 2. Deploy to a preview channel

```powershell
firebase hosting:channel:deploy phase1b --expires 7d
```

### 3. Test on the preview URL

Do this on a phone and in your main Chrome profile. The preview uses the **live** Firestore, so any review you submit is real data.

**First, check `/app/` doesn't redirect to itself.** This is the one thing no local tool could confirm, and a loop here would break every sticker. Replace `<preview>` with the preview URL:

```powershell
curl.exe -sIL --max-redirs 5 https://<preview>/app/
curl.exe -sIL --max-redirs 5 https://<preview>/app
```

Each must end in `200` within one redirect. If you see a chain of `301`s or `Maximum redirects followed`, stop here and don't deploy to live.

**Then check the headers:**

```powershell
curl.exe -sI https://<preview>/
curl.exe -sI https://<preview>/app/
curl.exe -sI https://<preview>/flutter_service_worker.js
```

All three need `cache-control: no-cache`, `x-content-type-options: nosniff` and `x-frame-options: DENY`. `/app/` also needs `x-robots-tag: noindex`.

**Then the pages:**

- The landing page, at every width you care about.
- `/app/`: log in as admin. If login fails with an unauthorized-domain error, add the preview host under Authentication > Settings > Authorized domains.
- The shim: open `https://<preview>/#/review/<shopId>` with one of your own shops. It must end at `/app/#/review/<shopId>` and show the review form.
- The short link: open `https://<preview>/r/<shopId>`. It must show the same form.

### 4. Build strictly

```powershell
.\deploy.ps1
```

This must finish without errors.

### 5. Deploy to live

```powershell
firebase deploy --only hosting
```

### 6. Check real stickers

- Scan a real printed sticker. It opens `https://qrcode-16b68.web.app/#/review/<id>`.
- Type `https://fullstarqr.com/#/review/<id>` into a browser.

Both must end on the review form. See `STICKER_TEST_PLAN.md` for the full list.

### 7. Later, separately: www

Add `www.fullstarqr.com` in Firebase as a redirect to the apex, and fix the GoDaddy `www` record as the console instructs.

### 8. Much later, only after all of the above passes: new QR codes

Flip `useNewDomain` to `true` in `lib/utils/app_config.dart` in its own commit, redeploy, and verify a freshly generated QR. Existing QR codes keep their stored URL, so old stickers aren't affected.

## Rollback

Firebase console > Hosting > release history > roll back to the previous release.

That restores the old site at `/`, with the app at the root. Firestore rules aren't part of a hosting release, so the phase 1a rules stay as they are.
