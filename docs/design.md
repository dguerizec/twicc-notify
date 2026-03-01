# TwiCC Notify — Design Document

## Overview

**TwiCC Notify** is a cross-platform (Android, macOS) Flutter application that runs as a background service, connects to a TwiCC instance via WebSocket, and delivers native push notifications when Claude requires user attention. Tapping a notification opens Chrome to the relevant TwiCC page.

## Goals

- Receive real-time notifications from TwiCC without keeping the browser open
- Play a sound and show a native notification when Claude enters `user_turn` state
- Deep-link to the relevant session on tap
- Minimize battery usage with configurable poll/reconnect intervals
- Authenticate through Cloudflare Access (Google OAuth)

## Architecture

```
+-------------------+       WSS        +-------------------+
|  TwiCC Notify     | <--------------> |  TwiCC Server     |
|  (Flutter app)    |   /ws/           |  (Django ASGI)    |
+-------------------+                  +-------------------+
        |
        v
  Native Notification
        |
        v
  Open Chrome → TwiCC session URL
```

### Authentication Flow

TwiCC instances behind Cloudflare Access require a valid `CF_Authorization` JWT cookie.

1. User enters the TwiCC URL in settings (e.g., `https://twicc.example.com`)
2. On "Connect", the app opens a WebView to the TwiCC URL
3. Cloudflare Access redirects to Google OAuth login
4. After successful auth, the WebView receives the `CF_Authorization` cookie
5. The app extracts and stores the JWT token
6. All subsequent WebSocket connections include the JWT as a cookie header
7. When the JWT expires (Cloudflare Access tokens typically last 24h), the app re-opens the WebView for re-authentication

If no Cloudflare Access is configured (direct access), the WebView step is skipped and the app connects directly.

### WebSocket Protocol

The app connects to `wss://<host>/ws/` and listens for JSON messages.

#### Messages consumed by the app

**`active_processes`** — Sent on connection, lists all currently active processes:
```json
{
  "type": "active_processes",
  "processes": [
    {
      "session_id": "claude-conv-xxx",
      "project_id": "...",
      "state": "user_turn",
      "started_at": 1740000000.0,
      "state_changed_at": 1740000060.0,
      "pending_request": { ... },
      "session_title": "Fix authentication bug",
      "project_name": "my-project"
    }
  ]
}
```

**`process_state`** — Broadcast on every state change:
```json
{
  "type": "process_state",
  "session_id": "claude-conv-xxx",
  "project_id": "...",
  "state": "user_turn",
  "started_at": 1740000000.0,
  "state_changed_at": 1740000060.0,
  "session_title": "Fix authentication bug",
  "project_name": "my-project",
  "pending_request": {
    "request_id": "...",
    "request_type": "permission",
    "tool_name": "Bash",
    "tool_input": { "command": "npm test" },
    "created_at": 1740000060.0
  }
}
```

**Process states:** `starting`, `assistant_turn`, `user_turn`, `dead`

#### Notification triggers

The app fires a notification when a process transitions **to `user_turn`** (from any other state). This indicates Claude has finished working and is waiting for user input.

The notification displays:
- **Title:** "Claude needs attention" (or similar)
- **Body:** "Project: {project_name}\nSession: {session_title}"
- **Sound:** Default notification sound (configurable)
- **Tap action:** Open Chrome to `https://<host>/sessions/<session_id>`

No notification is fired for:
- `starting` → normal startup
- `assistant_turn` → Claude is working, no action needed
- `dead` → process ended, nothing to do
- `user_turn` → `user_turn` (no actual transition)

## Settings Screen

Single screen with the following controls:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| TwiCC URL | Text field | (empty) | Base URL of the TwiCC instance |
| Connection | Toggle + status | Off | Connect/disconnect with status indicator |
| Sound | Toggle | On | Play sound on notification |
| Notifications | Toggle | On | Show native notifications |
| Poll interval | Slider/dropdown | 0 (realtime) | Interval in seconds between WebSocket reconnect attempts when idle. 0 = persistent connection (realtime). Higher values save battery by disconnecting between polls. Options: 0 (Realtime), 30s, 1min, 5min, 15min |

### Poll Interval Behavior

- **Realtime (0):** Maintains a persistent WebSocket connection. Lowest latency, highest battery usage. Recommended when plugged in.
- **30s – 15min:** The app connects, receives `active_processes`, checks for `user_turn` states, then disconnects. Reconnects after the configured interval. If a `user_turn` state is detected, the app stays connected until the user acknowledges or the state changes.

### Connection Status Indicator

Shows one of:
- **Disconnected** (gray) — Not connected
- **Connecting...** (yellow) — WebSocket handshake in progress
- **Connected** (green) — WebSocket open, receiving messages
- **Auth required** (orange) — JWT expired, needs re-authentication
- **Error** (red) — Connection failed (with error message)

## Data Persistence

Using `shared_preferences` (Flutter):

| Key | Type | Description |
|-----|------|-------------|
| `twicc_url` | String | TwiCC instance URL |
| `cf_jwt` | String | Cloudflare Access JWT token |
| `sound_enabled` | bool | Sound notification toggle |
| `notifications_enabled` | bool | Native notification toggle |
| `poll_interval` | int | Poll interval in seconds (0 = realtime) |
| `auto_connect` | bool | Auto-connect on app launch |

## Reconnection Strategy

When the WebSocket connection drops unexpectedly:

1. Wait 1 second, then attempt reconnect
2. On failure, exponential backoff: 1s → 2s → 4s → 8s → 16s → 30s (capped)
3. Reset backoff on successful connection
4. If JWT expired (4001 close code or HTTP 401), trigger re-authentication flow
5. In poll mode, the reconnect timer restarts from the poll interval

## Platform-Specific Notes

### Android
- Background service using `flutter_background_service` or `workmanager`
- Foreground notification required for persistent background execution
- Battery optimization: poll mode recommended for non-charging scenarios
- Wake lock management for reliable notification delivery

### macOS
- Menu bar app (no dock icon)
- Background execution via `launchd` or native macOS app lifecycle
- Native notifications via `flutter_local_notifications`

## Dependencies

| Package | Purpose |
|---------|---------|
| `web_socket_channel` | WebSocket client |
| `webview_flutter` | Cloudflare Access authentication |
| `flutter_local_notifications` | Native notification display |
| `shared_preferences` | Settings persistence |
| `url_launcher` | Open Chrome/browser on notification tap |
| `flutter_background_service` | Android background execution |

## Project Structure

```
twicc-notify/
├── docs/
│   └── design.md              # This file
├── lib/
│   ├── main.dart              # App entry point
│   ├── models/
│   │   └── process_state.dart # ProcessState model
│   ├── services/
│   │   ├── websocket_service.dart    # WebSocket connection management
│   │   ├── notification_service.dart # Native notification handling
│   │   └── auth_service.dart         # Cloudflare Access authentication
│   ├── screens/
│   │   └── settings_screen.dart      # Main (and only) settings screen
│   └── utils/
│       └── preferences.dart          # shared_preferences wrapper
├── android/                   # Android platform files
├── macos/                     # macOS platform files
├── pubspec.yaml               # Flutter dependencies
└── README.md                  # Setup and build instructions
```

## Security Considerations

- JWT token stored in `shared_preferences` (encrypted on Android via EncryptedSharedPreferences if needed)
- No credentials stored in plain text
- WebSocket connections always over WSS (TLS)
- The app never stores or transmits TwiCC session content, only state notifications
