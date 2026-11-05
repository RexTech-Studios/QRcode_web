# Firestore rules test plan (phase 1a)

Run this after the rules are deployed (step 6 of `DEPLOY_PHASE_1A.md`). Every test goes straight to the Firestore REST API, so it tests the rules and not the app.

**Expected results:** `200` means allowed. `403` with `PERMISSION_DENIED` means denied. Anything else, such as a `400` or `404`, means the test itself went wrong, so fix it and rerun rather than counting it as a pass.

These tests hit the live database. They create `feedback` documents named `rules-test-*`, which the last section deletes. Use one of your own shops.

## Setup

Run in Git Bash. Passwords are read with `read -s` so they stay out of your shell history. Never paste them into a file.

```bash
PROJECT=qrcode-16b68
BASE="https://firestore.googleapis.com/v1/projects/$PROJECT/databases/(default)/documents"
SHOP_ID="<one of your own shop ids>"
API_KEY="<web apiKey from lib/firebase_options.dart line 32>"

# status: prints only the HTTP status code of a request
status() { curl -s -o /dev/null -w "%{http_code}\n" "$@"; }

# token: signs in and prints an ID token
token() {
  read -r -p "Email: " EMAIL
  read -r -s -p "Password: " PASSWORD; echo
  curl -s "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"returnSecureToken\":true}" \
    | sed -n 's/.*"idToken": *"\([^"]*\)".*/\1/p'
  unset PASSWORD
}

# feedback <doc id> <extra JSON fields>: creates a feedback doc with a
# server-set createdAt, the same way the app's serverTimestamp() does
feedback() {
  local id="$1" fields="$2"; shift 2
  status -X POST "$BASE:commit" -H "Content-Type: application/json" "$@" -d "{
    \"writes\": [{
      \"update\": {
        \"name\": \"projects/$PROJECT/databases/(default)/documents/feedback/$id\",
        \"fields\": { $fields }
      },
      \"updateTransforms\": [{ \"fieldPath\": \"createdAt\", \"setToServerValue\": \"REQUEST_TIME\" }],
      \"currentDocument\": { \"exists\": false }
    }]
  }"
}

VALID="\"shopId\": {\"stringValue\": \"$SHOP_ID\"}, \"rating\": {\"integerValue\": \"5\"}"
```

## 1. Anonymous visitor

| # | Test | Command | Expected |
|---|---|---|---|
| 1.1 | Get one shop | `status "$BASE/shops/$SHOP_ID"` | 200 |
| 1.2 | List shops | `status "$BASE/shops"` | 403 |
| 1.3 | Write to a shop | `status -X PATCH "$BASE/shops/$SHOP_ID?updateMask.fieldPaths=rulesTest" -H "Content-Type: application/json" -d '{"fields":{"rulesTest":{"booleanValue":true}}}'` | 403 |
| 1.4 | Delete a shop | `status -X DELETE "$BASE/shops/$SHOP_ID"` | 403 |
| 1.5 | List QR codes | `status "$BASE/qr_codes"` | 403 |
| 1.6 | List feedback | `status "$BASE/feedback"` | 403 |
| 1.7 | Read any other collection | `status "$BASE/anything_else"` | 403 |

If 1.4 ever returns 200, stop and run the rollback in `DEPLOY_PHASE_1A.md`, then restore the shop from your JSON backup.

## 2. Anonymous feedback

| # | Test | Command | Expected |
|---|---|---|---|
| 2.1 | Valid feedback, no comment | `feedback rules-test-1 "$VALID"` | 200 |
| 2.2 | Valid, with a comment | `feedback rules-test-2 "$VALID, \"comment\": {\"stringValue\": \"rules test\"}"` | 200 |
| 2.3 | Valid, null comment (what the app sends) | `feedback rules-test-3 "$VALID, \"comment\": {\"nullValue\": null}"` | 200 |
| 2.4 | Old client, with `emailNotificationStatus` | `feedback rules-test-4 "$VALID, \"emailNotificationStatus\": {\"stringValue\": \"pending\"}"` | 200 |
| 2.5 | Rating 9 | `feedback rules-test-5 "\"shopId\": {\"stringValue\": \"$SHOP_ID\"}, \"rating\": {\"integerValue\": \"9\"}"` | 403 |
| 2.6 | Rating 0 | `feedback rules-test-6 "\"shopId\": {\"stringValue\": \"$SHOP_ID\"}, \"rating\": {\"integerValue\": \"0\"}"` | 403 |
| 2.7 | Rating as text | `feedback rules-test-7 "\"shopId\": {\"stringValue\": \"$SHOP_ID\"}, \"rating\": {\"stringValue\": \"5\"}"` | 403 |
| 2.8 | Extra field | `feedback rules-test-8 "$VALID, \"extra\": {\"stringValue\": \"x\"}"` | 403 |
| 2.9 | Comment over 250 characters | `feedback rules-test-9 "$VALID, \"comment\": {\"stringValue\": \"$(printf 'x%.0s' {1..251})\"}"` | 403 |
| 2.10 | Shop that doesn't exist | `feedback rules-test-10 "\"shopId\": {\"stringValue\": \"no-such-shop\"}, \"rating\": {\"integerValue\": \"5\"}"` | 403 |
| 2.11 | Client-chosen `createdAt` | See below | 403 |
| 2.12 | Update existing feedback | `status -X PATCH "$BASE/feedback/rules-test-1?updateMask.fieldPaths=rating" -H "Content-Type: application/json" -d '{"fields":{"rating":{"integerValue":"1"}}}'` | 403 |
| 2.13 | Delete feedback | `status -X DELETE "$BASE/feedback/rules-test-1"` | 403 |

Test 2.11 needs a plain create with no server timestamp:

```bash
status -X POST "$BASE/feedback?documentId=rules-test-11" -H "Content-Type: application/json" \
  -d "{\"fields\": { $VALID, \"createdAt\": {\"timestampValue\": \"2020-01-01T00:00:00Z\"} }}"
```

## 3. Signed-in non-admin

Create a throwaway user in the Firebase console (Authentication > Users > Add user), then:

```bash
USER_TOKEN=$(token)
AUTH=(-H "Authorization: Bearer $USER_TOKEN")
echo "${#USER_TOKEN}"   # must be well above 0, otherwise sign-in failed
```

| # | Test | Command | Expected |
|---|---|---|---|
| 3.1 | List shops | `status "${AUTH[@]}" "$BASE/shops"` | 403 |
| 3.2 | Write to a shop | `status -X PATCH "${AUTH[@]}" "$BASE/shops/$SHOP_ID?updateMask.fieldPaths=rulesTest" -H "Content-Type: application/json" -d '{"fields":{"rulesTest":{"booleanValue":true}}}'` | 403 |
| 3.3 | List QR codes | `status "${AUTH[@]}" "$BASE/qr_codes"` | 403 |
| 3.4 | List feedback | `status "${AUTH[@]}" "$BASE/feedback"` | 403 |
| 3.5 | Delete feedback | `status -X DELETE "${AUTH[@]}" "$BASE/feedback/rules-test-1"` | 403 |
| 3.6 | Read any other collection | `status "${AUTH[@]}" "$BASE/anything_else"` | 403 |

Delete the throwaway user from the console when you finish.

## 4. Admin

```bash
ADMIN_TOKEN=$(token)
ADMIN=(-H "Authorization: Bearer $ADMIN_TOKEN")
echo "${#ADMIN_TOKEN}"
```

| # | Test | Command | Expected |
|---|---|---|---|
| 4.1 | List shops | `status "${ADMIN[@]}" "$BASE/shops"` | 200 |
| 4.2 | List QR codes | `status "${ADMIN[@]}" "$BASE/qr_codes"` | 200 |
| 4.3 | List feedback | `status "${ADMIN[@]}" "$BASE/feedback"` | 200 |
| 4.4 | Write to a shop | `status -X PATCH "${ADMIN[@]}" "$BASE/shops/$SHOP_ID?updateMask.fieldPaths=rulesTest" -H "Content-Type: application/json" -d '{"fields":{"rulesTest":{"booleanValue":true}}}'` | 200 |
| 4.5 | Remove that field again | `status -X PATCH "${ADMIN[@]}" "$BASE/shops/$SHOP_ID?updateMask.fieldPaths=rulesTest" -H "Content-Type: application/json" -d '{"fields":{}}'` | 200 |
| 4.6 | Update feedback | `status -X PATCH "${ADMIN[@]}" "$BASE/feedback/rules-test-1?updateMask.fieldPaths=rating" -H "Content-Type: application/json" -d '{"fields":{"rating":{"integerValue":"1"}}}'` | 200 |

## 5. Clean up

Only 2.1 to 2.4 should have created documents. Deleting a missing document also returns 200, so this is safe if some were never created.

```bash
for id in 1 2 3 4; do status -X DELETE "${ADMIN[@]}" "$BASE/feedback/rules-test-$id"; done
unset ADMIN_TOKEN USER_TOKEN ADMIN AUTH API_KEY
```

Then check in the Firebase console that no `rules-test-*` documents remain in `feedback`, and that your test shop has no `rulesTest` field.
