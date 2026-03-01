# TwiCC Notify

Cross-platform (Android, macOS) background notification service for [TwiCC](https://github.com/twidi/twicc). Connects to a TwiCC instance via WebSocket and delivers native push notifications when Claude needs your attention.

## Features

- Real-time notifications when Claude enters `user_turn` state
- Tap notification to open the TwiCC session in your browser
- Cloudflare Access authentication (Google OAuth) via WebView
- Configurable poll interval to optimize battery usage
- Auto-connect on launch

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) >= 3.16
- For Android: Android Studio with Android SDK
- For macOS: Xcode with macOS SDK

## Setup

### 1. Initialize Flutter project

Since the `android/` and `macos/` platform directories need to be generated for your specific Flutter SDK version:

```bash
cd twicc-notify

# Create the full Flutter project structure around existing code
flutter create --project-name twicc_notify --org net.guerizec .

# This will NOT overwrite existing lib/ files, but will generate:
# - android/ (full platform directory)
# - macos/ (full platform directory)
# - test/
# - analysis_options.yaml
# - etc.
```

### 2. Apply platform configurations

**Android** — merge the permissions and service declarations from `android/app/src/main/AndroidManifest.xml` (the reference template) into the generated manifest.

**macOS** — ensure the entitlements in `macos/Runner.entitlements` (reference template) are present in the generated `macos/Runner/Release.entitlements` and `macos/Runner/DebugProfile.entitlements`.

### 3. Install dependencies

```bash
flutter pub get
```

### 4. Run

```bash
# Android
flutter run -d android

# macOS
flutter run -d macos
```

## Configuration

1. Launch the app
2. Enter your TwiCC URL (e.g., `https://twicc.example.com`)
3. Tap **Connect**
4. If behind Cloudflare Access: complete Google OAuth in the WebView
5. Adjust notification and battery settings as needed

## Battery Optimization

The **Poll interval** setting controls battery vs. latency tradeoff:

| Mode | Behavior | Battery |
|------|----------|---------|
| Realtime | Persistent WebSocket connection | Higher |
| 30s - 15min | Periodic connect → check → disconnect | Lower |

For mobile use on battery, 1-5 minute intervals are recommended.

## Architecture

See [docs/design.md](docs/design.md) for the full design document.
