# TextSnip

Tap a floating button over any app, drag a rectangle around any text on screen, and get a clean copy instantly. Everything runs on-device — your screen content is never uploaded anywhere.

> Android only · Requires Android 7.0 (API 24)+

---

## Features

- **Floating bubble** — persists above all apps via `SYSTEM_ALERT_WINDOW`
- **Region selection** — draw a rectangle over any part of the screen
- **On-device OCR** — Google ML Kit Latin text recognition, no network required
- **Edit before copying** — result screen lets you tweak the extracted text
- **Copy or Share** — one tap to clipboard or any share target
- **Privacy first** — captured images are deleted immediately after OCR

## How it works

1. Grant the overlay and notification permissions on first launch
2. Tap **Start bubble** and accept Android's screen-capture prompt — a floating button appears over all other apps
3. Navigate to the app and screen you want to extract text from
4. Tap the bubble → drag a selection rectangle around the text
5. TextSnip captures that region, runs OCR, and brings you back to the result

## Tech stack

| Layer | Technology |
|---|---|
| UI | Flutter (Material 3) |
| Overlay | `flutter_overlay_window` |
| Screen capture | Android `MediaProjection` API + foreground service |
| OCR | Google ML Kit Text Recognition (on-device) |
| Share | `share_plus` |

## Building from source

### Prerequisites

- Flutter 3.41 or newer (Dart SDK ≥ 3.11.3)
- Android SDK with the API 36 platform (`compileSdk = 36`, `targetSdk = 35`)
- NDK `28.2.13676358` (for ML Kit native libs)
- A physical Android device or emulator running API 24+

### Run in debug mode

```bash
git clone https://github.com/RhenGTL/textsnip.git
cd textsnip
flutter pub get
flutter run
```

### Build a release APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Install on a connected device

```bash
flutter run --release
```

## Permissions

| Permission | Why |
|---|---|
| `SYSTEM_ALERT_WINDOW` | Draw the floating bubble above other apps |
| `FOREGROUND_SERVICE` | Keep the screen-capture service alive for the whole bubble session |
| `FOREGROUND_SERVICE_MEDIA_PROJECTION` | Required on Android 14+ for screen capture |
| `FOREGROUND_SERVICE_SPECIAL_USE` | Required by the overlay window service |
| `POST_NOTIFICATIONS` | Show the persistent session notification, which has a Stop action (Android 13+) |

## License

MIT
