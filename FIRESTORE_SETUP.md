# Firestore Security Rules – Setup Steps

## What’s in place

- `firestore.rules` – Security rules for your collections
- `firebase.json` – Config for deploying rules via Firebase CLI

---

## Option A: Deploy via Firebase Console (no CLI)

1. Open [Firebase Console](https://console.firebase.google.com) → your project
2. Go to **Firestore Database** → **Rules**
3. Replace the existing rules with the contents of `firestore.rules`
4. Click **Publish**

---

## Option B: Deploy via Firebase CLI

### 1. Install Firebase CLI (if needed)

```bash
npm install -g firebase-tools
```

### 2. Log in and select project

```bash
firebase login
firebase use silent-morse-messenger
```

(Use your actual project ID if it differs.)

### 3. Deploy rules

```bash
firebase deploy --only firestore:rules
```

---

## What the rules enforce

| Collection | Read | Write |
|------------|------|-------|
| `users/{userId}` | Any signed-in user | Only the owner |
| `users/{userId}/contacts` | Only the owner | Only the owner |
| `chats/{chatId}` | Only participants | Only participants |
| `chats/{chatId}/messages` | Only participants | Only participants |
| `usernames/{username}` | Any signed-in user | Authenticated users |

---

## Verify

1. In Firebase Console → **Firestore** → **Rules**
2. Confirm the rules match what you expect
3. Use the **Rules Playground** to test read/write scenarios
