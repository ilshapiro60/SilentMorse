# SilentMorse

A Morse code messenger. Communicate in the dark using haptics and touch.

## Features

- **Morse code messaging**: Send and receive messages as vibration patterns
- **Dark Screen Mode**: Near-black screen with touch-active Morse input (short tap = dot, long press = dash)
- **1-on-1 chat**: Real-time messaging via Firebase Firestore
- **Auth**: Google Sign-In, Anonymous/Guest (Phone auth coming soon)
- **Username lookup**: Find contacts by @username

## Setup

1. **SDK**: Ensure the SDK is installed (`flutter --version`)

2. **Create platform folders** (if missing): Run `flutter create .` to add `android/`, `ios/`, etc.

3. **Firebase**: Copy your Firebase config from the Android project:
   - Run `flutterfire configure` to generate `lib/firebase_options.dart`
   - Or manually add `google-services.json` to `android/app/` and `GoogleService-Info.plist` to `ios/Runner/`

4. **Dependencies**:
   ```bash
   cd SilentMorse
   flutter pub get
   ```

5. **Firebase Console**: Ensure these are configured:
   - Authentication (Google, Anonymous)
   - Firestore (same schema as Kotlin app)
   - Cloud Functions (`createChat`, `claimUsername`, `onMessageCreated`)

## Project Structure

```
lib/
├── main.dart              # App entry, providers
├── app.dart               # Router, navigation
├── data/
│   └── models.dart        # User, Chat, Message, MorseSettings, etc.
├── services/
│   ├── auth_service.dart  # Firebase Auth, Google Sign-In
│   └── chat_repository.dart  # Firestore CRUD
├── util/
│   ├── morse_haptic_engine.dart  # Text↔Morse, haptic playback
│   └── tap_decoder.dart   # Press timing → Morse → text
└── ui/
    ├── auth/              # AuthScreen (Google, Guest, Username)
    ├── contacts/          # ContactsScreen, AddContactSheet
    └── chat/              # ChatScreen, DarkScreenMode
```

## Backend

Uses the same Firebase Cloud Functions as the Kotlin app. Deploy with:

```bash
cd ../functions
firebase deploy --only functions
```

## Run

```bash
flutter run
```

## Platform Notes

- **Android**: Vibration and screen brightness work out of the box
- **iOS**: Vibration may require additional setup; screen brightness has limitations
- **Web**: Vibration API support varies by browser
