import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

import '../models/process_state.dart';
import '../utils/preferences.dart';
import 'auth_service.dart';
import 'background_service.dart';
import 'notification_service.dart';
import 'quota_service.dart';
import 'stats_service.dart';

/// Connection state for the UI.
enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  authRequired,
  error,
}

/// Manages the WebSocket connection to TwiCC.
///
/// Supports two modes:
/// - **Realtime** (pollInterval = 0): persistent WebSocket connection
/// - **Polling** (pollInterval > 0): connects periodically, checks state, disconnects
///
/// Implements exponential backoff for unexpected disconnections.
class WebSocketService extends ChangeNotifier {
  final AppPreferences _prefs;
  final AuthService _auth;
  final NotificationService _notifications;
  final StatsService _stats;
  final QuotaService _quotas;

  IOWebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _pollTimer;
  Timer? _pingTimer;

  WsConnectionState _state = WsConnectionState.disconnected;
  String? _errorMessage;
  int _reconnectAttempts = 0;
  bool _intentionalDisconnect = false;

  /// Whether the user has requested the service to be active.
  bool _active = false;

  /// Monotonically increasing connection generation counter.
  ///
  /// Incremented each time [_connect] creates a new WebSocket connection.
  /// Used by the [_onDone] closure to detect stale close events from
  /// previous connections that fire after a new connection has already
  /// been established — preventing leaked stream listeners.
  int _connectionGeneration = 0;

  /// Maximum reconnect delay in seconds.
  static const int _maxReconnectDelay = 30;

  /// Ping interval to keep the connection alive through proxies (Cloudflare, nginx).
  static const int _pingIntervalSeconds = 30;

  WebSocketService(this._prefs, this._auth, this._notifications, this._stats, this._quotas);

  WsConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _state == WsConnectionState.connected;
  bool get isActive => _active;

  /// Start the service. Connects immediately and sets up polling if configured.
  /// Also starts an Android foreground service to keep the process alive
  /// when the app is in the background.
  void start() {
    _active = true;
    _intentionalDisconnect = false;
    startForegroundService();
    _connect();
  }

  /// Stop the service. Disconnects and cancels all timers.
  /// Also stops the Android foreground service.
  void stop() {
    _active = false;
    _intentionalDisconnect = true;
    _cancelTimers();
    _disconnect();
    _notifications.reset();
    stopForegroundService();
  }

  /// Connect to the TwiCC WebSocket.
  ///
  /// Awaits the underlying TCP/TLS handshake (`channel.ready`) before
  /// marking the connection as established. This ensures exponential
  /// backoff works correctly — `_reconnectAttempts` is only reset after
  /// a confirmed connection, not after every attempt.
  Future<void> _connect() async {
    if (_state == WsConnectionState.connecting || _state == WsConnectionState.connected) return;

    final baseWsUrl = _prefs.wsUrl;
    if (baseWsUrl == null) {
      _setState(WsConnectionState.error);
      _errorMessage = 'No TwiCC URL configured';
      notifyListeners();
      return;
    }

    // Request only the message types we need. If the server doesn't
    // support this parameter it simply ignores it (backward compatible).
    final wsUrl = '${baseWsUrl}?subscribe=process_state,active_processes,usage_updated';

    // Clean up any stale resources from a previous connection before
    // creating a new one. This prevents leaked stream listeners when
    // _onDone() from a previous connection fires late and overwrites
    // our fields, leaving orphaned subscriptions.
    _stopPingTimer();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;

    // Bump generation so any late-firing _onDone from a previous
    // connection will be ignored.
    final generation = ++_connectionGeneration;

    _setState(WsConnectionState.connecting);
    _errorMessage = null;

    try {
      final channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: _auth.wsHeaders,
      );

      // Wait for the WebSocket handshake to complete.
      // This throws if DNS resolution, TCP connect, or TLS handshake fails.
      await channel.ready;

      // If stop() was called while we were awaiting, discard the channel.
      if (!_active) {
        channel.sink.close();
        return;
      }

      // If another _connect() was called while we were awaiting (should not
      // happen due to state guard, but be defensive), discard this channel.
      if (generation != _connectionGeneration) {
        debugPrint('[TwiCC] Discarding stale connection (gen $generation, current $_connectionGeneration)');
        channel.sink.close();
        return;
      }

      _channel = channel;
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: () => _onDone(generation),
      );

      _setState(WsConnectionState.connected);
      _reconnectAttempts = 0;
      _startPingTimer();
      debugPrint('[TwiCC] WebSocket connected (gen $generation) to $wsUrl');
      updateForegroundNotification('TwiCC Notify', 'Connected — monitoring Claude sessions');
    } catch (e) {
      _channel = null;
      _setState(WsConnectionState.error);
      _errorMessage = e.toString();
      debugPrint('[TwiCC] WebSocket connect failed (attempt $_reconnectAttempts): $e');
      updateForegroundNotification('TwiCC Notify', 'Reconnecting…');
      _scheduleReconnect();
    }
  }

  /// Disconnect from the WebSocket.
  void _disconnect() {
    _stopPingTimer();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _setState(WsConnectionState.disconnected);
  }

  /// Handle an incoming WebSocket message.
  void _onMessage(dynamic data) {
    if (data is! String) return;

    _stats.recordReceived(utf8.encode(data).length);

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == 'process_state' || type == 'active_processes') {
        final sid = json['session_id'] as String?;
        final state = json['state'] as String?;
        debugPrint('[TwiCC] WS <<< $type${sid != null ? ' session=${sid.substring(0, 12)}… state=$state' : ''}');
      }

      switch (type) {
        case 'active_processes':
          _handleActiveProcesses(json);
          break;
        case 'process_state':
          _handleProcessState(json);
          break;
        case 'pong':
          break; // Expected response to our ping heartbeat
        case 'usage_updated':
          _quotas.handleUsageUpdated(json);
          break;
        case 'auth_failure':
          _handleAuthFailure();
          break;
        // Ignore all other message types (session updates, etc.)
      }
    } catch (e) {
      debugPrint('[TwiCC] Failed to parse WS message: $e');
    }
  }

  /// Handle the `active_processes` message sent on connection.
  void _handleActiveProcesses(Map<String, dynamic> json) {
    final processes = (json['processes'] as List<dynamic>?)
        ?.map((p) => ProcessStateInfo.fromJson(p as Map<String, dynamic>))
        .toList();

    if (processes != null) {
      _notifications.handleActiveProcesses(processes);
    }

    // In poll mode, disconnect after receiving the initial state
    _maybeDisconnectForPoll();
  }

  /// Handle a `process_state` broadcast message.
  void _handleProcessState(Map<String, dynamic> json) {
    final info = ProcessStateInfo.fromJson(json);
    _notifications.handleProcessState(info);
  }

  /// Handle authentication failure from TwiCC.
  ///
  /// Clears all stored credentials (CF JWT and session cookie) since
  /// the server rejected our authentication.
  void _handleAuthFailure() {
    _disconnect();
    _setState(WsConnectionState.authRequired);
    _auth.clearAll();
  }

  /// Called when the WebSocket stream encounters an error.
  void _onError(dynamic error) {
    debugPrint('[TwiCC] WebSocket stream error: $error');
    _errorMessage = error.toString();
    _setState(WsConnectionState.error);
  }

  /// Called when a WebSocket connection closes.
  ///
  /// The [generation] parameter identifies which connection closed.
  /// If a newer connection has already been established (generation mismatch),
  /// this close event is stale and must be ignored to prevent overwriting
  /// the new connection's state and leaking stream listeners.
  void _onDone(int generation) {
    // Ignore stale close events from previous connections.
    // This prevents the race condition where a late-firing _onDone
    // overwrites _channel/_subscription of a newer, active connection,
    // leaking the newer subscription and causing duplicate message delivery.
    if (generation != _connectionGeneration) {
      debugPrint('[TwiCC] Ignoring stale WebSocket close (gen $generation, current $_connectionGeneration)');
      return;
    }

    final closeCode = _channel?.closeCode;
    final closeReason = _channel?.closeReason;
    debugPrint('[TwiCC] WebSocket closed (gen $generation): code=$closeCode reason=$closeReason');

    _stopPingTimer();
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    if (!_intentionalDisconnect && _active) {
      // Check if it was an auth failure (close code 4001)
      if (closeCode == 4001) {
        _handleAuthFailure();
        return;
      }

      _setState(WsConnectionState.disconnected);
      _scheduleReconnect();
    } else {
      _setState(WsConnectionState.disconnected);
    }
  }

  /// Schedule a reconnection with exponential backoff.
  ///
  /// Realtime mode: 1s, 2s, 4s, 8s, 16s, 30s, 30s, …
  /// Poll mode: always uses the configured poll interval.
  void _scheduleReconnect() {
    if (!_active) return;

    final pollInterval = _prefs.pollInterval;
    final int delay;

    if (pollInterval > 0) {
      // In poll mode, use the poll interval
      delay = pollInterval;
    } else {
      // In realtime mode, use exponential backoff (min 1s)
      delay = min(
        max(1, pow(2, _reconnectAttempts).toInt()),
        _maxReconnectDelay,
      );
    }

    _reconnectAttempts++;
    debugPrint('[TwiCC] Scheduling reconnect in ${delay}s (attempt $_reconnectAttempts)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (_active) _connect();
    });
  }

  /// In poll mode, disconnect after receiving initial state.
  /// Schedule the next poll connection.
  void _maybeDisconnectForPoll() {
    final pollInterval = _prefs.pollInterval;
    if (pollInterval <= 0) return; // Realtime mode, stay connected

    // Disconnect and schedule next poll
    _intentionalDisconnect = true;
    _disconnect();
    _intentionalDisconnect = false;

    _pollTimer?.cancel();
    _pollTimer = Timer(Duration(seconds: pollInterval), () {
      if (_active) _connect();
    });
  }

  /// Start the periodic ping heartbeat to keep the connection alive.
  ///
  /// Sends `{"type":"ping"}` every 30s, matching the TwiCC frontend behavior.
  /// Prevents Cloudflare, nginx, and other reverse proxies from closing
  /// idle WebSocket connections.
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(
      const Duration(seconds: _pingIntervalSeconds),
      (_) => _sendPing(),
    );
  }

  /// Stop the ping heartbeat timer.
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Send a ping message to the server.
  void _sendPing() {
    if (_channel != null && _state == WsConnectionState.connected) {
      try {
        final payload = jsonEncode({'type': 'ping'});
        _channel!.sink.add(payload);
        _stats.recordSent(utf8.encode(payload).length);
      } catch (e) {
        debugPrint('[TwiCC] Failed to send ping: $e');
      }
    }
  }

  /// Cancel all pending timers.
  void _cancelTimers() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _stopPingTimer();
  }

  /// Update the connection state and notify listeners.
  void _setState(WsConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
