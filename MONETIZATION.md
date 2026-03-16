# Monetization Setup

Silent Morse uses **free with ads** + **$1.99 one-time purchase to remove ads**.

## Current State (Development)

- **AdMob**: Test ad unit IDs are used. Ads will show test banners.
- **In-app purchase**: Product ID `remove_ads` must be created in Google Play Console.

## Production Setup

### 1. AdMob (ads.google.com)

1. Create an AdMob account and app for Silent Morse.
2. Add a **Banner** ad unit for Android and iOS.
3. Replace IDs in:
   - `lib/services/ad_service.dart` – `_androidBannerId` and `_iosBannerId` (in production block)
   - `android/app/src/main/AndroidManifest.xml` – `com.google.android.gms.ads.APPLICATION_ID`
   - `ios/Runner/Info.plist` – `GADApplicationIdentifier`

### 2. Google Play Console (In-app products)

1. Open your app → **Monetize** → **Products** → **In-app products**.
2. Create product:
   - **Product ID**: `remove_ads` (must match `removeAdsProductId` in `purchase_service.dart`)
   - **Name**: Remove ads
   - **Description**: Remove all ads from Silent Morse forever.
   - **Price**: $1.99
   - **Type**: Non-consumable (one-time purchase)

3. Activate the product.

### 3. App Store Connect (iOS, when you publish)

1. Create an in-app purchase: **Non-consumable**.
2. Product ID: `remove_ads`
3. Price: $1.99

### 4. Testing

- **Ads**: Test IDs show sample ads. Use real device; emulator may have limited support.
- **IAP**: Add test users in Play Console → **Setup** → **License testing**. Use a signed release build (debug builds won't complete real purchases).
