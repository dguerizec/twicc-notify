# TwiCC Notify

Cross-platform (Android, macOS) background notification service for [TwiCC](https://github.com/twidi/twicc). Connects to a TwiCC instance via WebSocket and delivers native push notifications when Claude needs your attention.

## Features

- Real-time notifications when Claude enters `user_turn` state
- Tap notification to open the TwiCC session in your browser
- **Multi-mode authentication**: auto-detects the server setup
  - No auth (local/LAN)
  - TwiCC password (built-in password protection)
  - Cloudflare Access (Google OAuth via WebView)
- Configurable poll interval to optimize battery usage
- Audio alerts via media stream (works with BT headphones, even in DND)
- Headphone detection (audio only plays when headphones are connected)
- WebSocket statistics (messages, bytes, per time window)
- Auto-connect on launch

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) >= 3.16
- For Android: Android Studio with Android SDK
- For macOS: Xcode with macOS SDK

## Setup

### 1. Initialize Flutter project

Generate platform directories (`android/`, `macos/`) for your Flutter SDK version. Existing `lib/` files are not overwritten.

```bash
./scripts/init.sh
```

### 2. Apply platform configurations

**Android** — merge the permissions and service declarations from `android/app/src/main/AndroidManifest.xml` (the reference template) into the generated manifest.

**macOS** — ensure the entitlements in `macos/Runner.entitlements` (reference template) are present in the generated `macos/Runner/Release.entitlements` and `macos/Runner/DebugProfile.entitlements`.

### 3. Build & deploy

```bash
# Build + install on connected Android device (preserves app data)
./scripts/deploy.sh

# Deploy over WiFi (after pairing):
./scripts/deploy.sh --wifi

# Or step by step:
./scripts/build.sh      # Build release APK
./scripts/install.sh    # Install on device (preserves settings)

# Fresh install (wipes app data):
./scripts/clean-install.sh
```

### WiFi deployment (ADB over network)

Pair your device once, then deploy wirelessly:

```bash
# One-time pairing (get pairing info from Android Developer Options > Wireless debugging)
./scripts/wifi-pair.sh <pairing_ip:port> <pairing_code> <debug_port>

# Then deploy over WiFi
./scripts/deploy.sh --wifi
```

## Configuration

1. Launch the app
2. Enter your TwiCC URL (e.g., `https://twicc.example.com` or `http://192.168.1.x:3500`)
3. Tap **Connect**
4. The app auto-detects the authentication mode:
   - **No auth**: connects directly
   - **TwiCC password**: prompts for the password
   - **Cloudflare Access**: opens a WebView for Google OAuth
5. Adjust notification, audio alerts, and battery settings as needed

## Battery Optimization

The **Poll interval** setting controls battery vs. latency tradeoff:

| Mode | Behavior | Battery |
|------|----------|---------|
| Realtime | Persistent WebSocket connection | Higher |
| 30s - 15min | Periodic connect → check → disconnect | Lower |

For mobile use on battery, 1-5 minute intervals are recommended.

## Architecture

See [docs/design.md](docs/design.md) for the full design document.
