# Apple Sign-In Setup

Sign in with Apple works on **iOS** out of the box. For **Android**, you need extra configuration.

---

## Do you have to pay?

**Yes.** You need an **Apple Developer Program** membership: **$99/year**.

- Required to create App IDs, Service IDs, and configure Sign in with Apple
- No way to use Sign in with Apple without it
- [developer.apple.com/programs](https://developer.apple.com/programs/)

---

## iOS Setup (required for App Store)

1. **Apple Developer Portal** → Certificates, Identifiers & Profiles → **Identifiers**
2. Select your **App ID** (e.g. `com.silentmorse.messenger`)
3. Enable **Sign in with Apple**
4. In Xcode: **Runner** → **Signing & Capabilities** → add **Sign in with Apple**

---

## Android Setup (optional, for "Continue with Apple" on Android)

### Step 1: Create a Service ID

1. **Apple Developer Portal** → Identifiers → **+** → **Services IDs**
2. Description: `Silent Morse Android`
3. Identifier: `com.silentmorse.messenger.service` (or similar)
4. Enable **Sign in with Apple**
5. Click **Configure** next to Sign in with Apple:
   - **Primary App ID**: Select your iOS App ID
   - **Domains**: Your callback domain (e.g. `auth.yoursite.com`)
   - **Return URLs**: `https://auth.yoursite.com/callbacks/sign_in_with_apple`

### Step 2: Create a backend callback

You need a server endpoint that:

1. Receives the authorization code from Apple
2. Redirects back to your app with:  
   `intent://callback?<params>#Intent;package=com.silentmorse.messenger;scheme=signinwithapple;end`

Options:

- **Firebase Hosting + Cloud Function** – Host a redirect page
- **Your own server** – Any HTTPS endpoint
- **Third-party** – e.g. [Clerk](https://clerk.com), [Auth0](https://auth0.com)

### Step 3: Configure Silent Morse

Edit `lib/apple_signin_config.dart`:

```dart
const String appleSignInClientId = 'com.silentmorse.messenger.service';
const String appleSignInRedirectUri = 'https://auth.yoursite.com/callbacks/sign_in_with_apple';
```

Use the **Service ID** as `clientId` and your callback URL as `redirectUri`.

---

## Summary

| Platform | Setup | Cost |
|----------|-------|------|
| **iOS** | Enable in App ID + Xcode | $99/year (Apple Developer) |
| **Android** | Service ID + backend + config | Same $99/year |

**Without setup:** On Android, tapping "Continue with Apple" shows an error directing you to this file. On iOS, it works once the App ID and Xcode capabilities are configured.
