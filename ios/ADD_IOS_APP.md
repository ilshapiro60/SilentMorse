# Add iOS App to Firebase (for iPhone tester)

## 1. Add iOS app in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project **silent-morse-messenger**
3. Click the **iOS** (Apple) icon to add an app
4. Enter:
   - **Bundle ID:** `com.silentmorse.messenger`
   - **App nickname:** Silent Morse (optional)
5. Click **Register app**
6. **Download** `GoogleService-Info.plist`
7. Skip the remaining steps in the wizard (we'll add the file manually)

## 2. Add the file to the project

1. Move the downloaded `GoogleService-Info.plist` into:
   ```
   SilentMorse/ios/Runner/
   ```
2. In Xcode (or your IDE), add it to the Runner target:
   - Right-click `ios/Runner` folder → Add Files
   - Select `GoogleService-Info.plist`
   - Ensure "Copy items if needed" and Runner target are checked

## 3. Google Sign-In on iOS

For the tester to use Google Sign-In on iPhone:

1. In Firebase Console → Project Settings → Your apps → iOS app
2. Add the **SHA-1** of your iOS signing certificate (from Xcode or Apple Developer)
3. In [Google Cloud Console](https://console.cloud.google.com) → APIs & Services → Credentials
4. Ensure the iOS OAuth client has the correct bundle ID

## 4. Build for iPhone

```bash
flutter run -d <iphone-device-id>
```

Or open `ios/Runner.xcworkspace` in Xcode and run on a simulator or device.
