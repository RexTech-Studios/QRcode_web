# Deploying phase 1a

Follow the numbered steps in order, from the `phase-1a-auth-lockdown` branch. Nothing here has been deployed yet.

## Before you start

- [ ] Firebase console > Authentication: the Email/Password provider is enabled, and the admin user exists with the uid in `lib/utils/app_config.dart`.
- [ ] Authentication > Settings > User actions: turn off **Enable create (sign-up)**. The app has no sign-up, but otherwise anyone with the public API key can still create an account. Such an account gets no access, so this is tidiness rather than protection.
- [ ] If the web API key has HTTP referrer restrictions in Google Cloud Console, allow the preview domain too, or login will fail in step 3.
- [ ] Run `firebase functions:list`. The `functions/` folder is gone from the repo, but deleting it does **not** remove a deployed function. If `sendFeedbackEmailNotification` is listed, decide whether to delete it. It doesn't block this rollout.

## Steps

### 0. Confirm reviews work on live today

Submit a review on the live site under the current interim rules, using one of your own shops, and confirm it appears in Firestore. If this fails, stop: the problem already exists and is not caused by this release.

### 1. Back up

On the **live** site, open Settings and use Export as JSON.

This has to happen on the old build. It is the last export that includes the email and WhatsApp fields, since the new build no longer knows about them. Keep the file somewhere private, because it holds contact details, and don't commit it. The export does not include `feedback`.

### 2. Build and deploy to a preview channel

Never go straight to live.

```bash
flutter build web
firebase hosting:channel:deploy preview
```

### 3. Test on the preview URL

The preview uses the **live** Firestore, so everything here touches real data.

1. Log in as admin.
2. Confirm the backfill ran: in the Firebase console, shops that have a QR code now have a `qrCode` field. It only adds that one field.
3. Test an old-format link with your own shop: open `<preview URL>/#/review/<shopId>` and submit a review. Confirm it reaches Firestore. Try both a 1-3 star review (a row should appear in the shop's sheet, labelled with the QR code) and a 4-5 star review (Google should open).

Don't continue until all of this works.

### 4. Deploy hosting to live

```bash
firebase deploy --only hosting
```

### 5. Immediately deploy the rules

```bash
firebase deploy --only firestore:rules
```

Until this finishes, the new site is live but the database is still open, so don't pause here. If the rules fail to compile, the deploy is rejected and the old rules stay active.

### 6. Run the rules tests

Work through `RULES_TEST_PLAN.md`.

### 7. Wait at least 3-7 days, then scrub

Old clients need time to pick up the new build. Then open Settings > Maintenance, press **Remove legacy contact fields**, check the count, and confirm.

Until you press it, `notificationEmail` and `whatsappNumber` remain readable to anyone who fetches a shop by id, and the id is printed in every QR code.

## Rollback

Redeploy the previous interim rules. They are on `main`, not this branch:

```bash
git show main:firestore.rules > firestore.rules
firebase deploy --only firestore:rules
git checkout phase-1a-auth-lockdown -- firestore.rules
```

The last line puts the phase 1a rules back in your working copy. A rollback reopens the database to everyone, so treat it as a short-term measure.

The new site keeps working under the interim rules, because it still sends `emailNotificationStatus` (see below). To roll back the site as well, use Hosting > Release history > Rollback in the Firebase console.

## Follow-up after step 7

`lib/services/firebase_service.dart` still sends `emailNotificationStatus: 'pending'` with each review. The interim rules require that field, so removing it earlier would make step 3 fail, reject every customer review between steps 4 and 5, and break the rollback above.

Once you're confident you won't need to roll back:

1. Delete that key and its comment from `submitFeedback`.
2. Run `flutter build web` and `firebase deploy --only hosting`.

The phase 1a rules already treat the field as optional, so no rules change is needed. After this release, a rules rollback would need the site rolled back too.
