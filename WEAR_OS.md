# Wear OS Support

Silent Morse runs on Android Wear OS watches. The app automatically switches to the watch UI when the screen width is under 320px.

## Features on Watch

- **Contacts** – Compact list of your chats (synced from phone)
- **Morse tap** – Tap = dot, long press = dash, swipe up = send
- **Receive** – Haptic or text (per Settings on phone)
- **Ambient mode** – Minimal "··· −−− ···" display when watch is dimmed

## Setup

1. **Create a Wear OS emulator** in Android Studio:
   - Device Manager → Create Device → **Wear OS** form factor
   - Choose a watch (e.g. Pixel Watch)
   - Download a system image (API 30+)
   - Create and start the AVD

2. **Run on watch**:
   ```bash
   flutter run
   ```
   Select the Wear OS emulator when prompted.

3. **Or run on physical watch**:
   - Enable Developer Options on the watch
   - Connect via Bluetooth debugging (Android Studio) or USB
   - `flutter run -d <watch-device-id>`

## Notes

- Add contacts on your phone first; the watch shows synced contacts
- Ads are not shown on the watch
- Settings (vibration, receive mode) are shared with the phone app
