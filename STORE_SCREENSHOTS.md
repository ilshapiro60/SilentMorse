# Store Screenshot Requirements

## How Many Screenshots Needed

### App Store (iOS)
| Device | Size (portrait) | Min | Max |
|--------|-----------------|-----|-----|
| **iPhone 6.9"** (primary) | 1290 × 2796 px | 1 | 10 |
| iPhone 6.5" | 1284 × 2778 px | 1 | 10 |
| iPhone 6.3" | 1179 × 2556 px | 1 | 10 |
| iPhone 6.1" | 1170 × 2532 px | 1 | 10 |
| iPhone 5.5" | 1242 × 2208 px | 1 | 10 |
| **iPad 13"** (if iPad support) | 2064 × 2752 px | 1 | 10 |

**Minimum:** 1 screenshot per device size you support. **Recommended:** 3–6 per size.

**Practical minimum for iPhone-only:** 3–6 screenshots at 1290 × 2796 px (6.9" display).

### Google Play (Android)
| Asset | Size | Min | Max |
|-------|------|-----|-----|
| **Phone screenshots** | 1080 × 1920 px (portrait) | 2 | 8 |
| **Feature graphic** | 1024 × 500 px | 1 | 1 |
| Tablet (optional) | 1080 × 1920 or 1200 × 1920 | 4 | 8 |

**Minimum:** 2 phone screenshots + 1 feature graphic.

---

## Suggested Screens to Capture

1. **Auth** – Sign-in screen (Google/Apple buttons)
2. **Contacts** – Main chat list with sample conversations
3. **Chat** – Conversation view with messages
4. **Dark mode** – Morse haptic send/receive screen
5. **Settings** – Settings screen
6. **Practice** – Trainer or test screen (optional)

---

## Generating Screenshots

### Automated (recommended)

1. Start an iOS simulator or Android emulator:
   - **iOS:** iPhone 15 Pro Max (1290×2796) for App Store
   - **Android:** Phone (1080×1920) for Play Store

2. Run the screenshot capture:

```bash
# Main screens (Contacts, Chat, Settings)
flutter drive --driver=test_driver/integration_test.dart --target=lib/main_screenshot.dart

# Auth screen only
flutter drive --driver=test_driver/integration_test.dart --target=lib/main_screenshot_auth.dart
```

3. Screenshots are saved to `store_screenshots/`:
   - `00-auth.png` – Auth/sign-in screen (from auth run)
   - `01-contacts.png` – Contacts list
   - `02-chat.png` – Chat conversation
   - `03-settings.png` – Settings

### Manual

1. **iOS:** Run on iPhone 15 Pro Max simulator (6.9"), use Cmd+S to save screenshot.
2. **Android:** Run on emulator, use the camera button in the emulator toolbar.

### Feature graphic (Google Play)

Create a 1024×500 px banner. Use `assets/silent_morse_icon_v4.png` as reference or design in Figma/Canva.
