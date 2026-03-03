import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized access to persisted user preferences.
///
/// Wraps [SharedPreferences] for non-sensitive settings and
/// [FlutterSecureStorage] for credentials (JWT, session cookie).
/// Secure values are cached in memory for synchronous access.
class AppPreferences {
  static const _keyUrl = 'twicc_url';
  static const _keySoundEnabled = 'sound_enabled';
  static const _keyNotificationsEnabled = 'notifications_enabled';
  static const _keyPollInterval = 'poll_interval';
  static const _keyAutoConnect = 'auto_connect';
  static const _keyAudioAlertEnabled = 'audio_alert_enabled';
  static const _keyAudioAlertOnQuestion = 'audio_alert_on_question';
  static const _keyAudioAlertOnWaiting = 'audio_alert_on_waiting';
  static const _keyAcceptSelfSignedCerts = 'accept_self_signed_certs';
  static const _keyStatsBuckets = 'ws_stats_buckets';

  // Secure storage keys
  static const _keyCfJwt = 'cf_jwt';
  static const _keySessionCookie = 'session_cookie';

  late final SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  // In-memory cache for secure values (loaded at init, updated on write)
  String? _cfJwt;
  String? _sessionCookie;

  /// Initialize preferences and secure storage.
  ///
  /// Loads secure credentials into memory cache for synchronous access.
  /// Migrates credentials from SharedPreferences on first run.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _migrateToSecureStorage();
    _cfJwt = await _secure.read(key: _keyCfJwt);
    _sessionCookie = await _secure.read(key: _keySessionCookie);
  }

  /// Migrate credentials from SharedPreferences to secure storage.
  ///
  /// One-time migration for users updating from a version that stored
  /// tokens in plaintext. After migration, clears the old keys.
  Future<void> _migrateToSecureStorage() async {
    final oldJwt = _prefs.getString(_keyCfJwt);
    if (oldJwt != null && oldJwt.isNotEmpty) {
      await _secure.write(key: _keyCfJwt, value: oldJwt);
      await _prefs.remove(_keyCfJwt);
    }

    final oldSession = _prefs.getString(_keySessionCookie);
    if (oldSession != null && oldSession.isNotEmpty) {
      await _secure.write(key: _keySessionCookie, value: oldSession);
      await _prefs.remove(_keySessionCookie);
    }
  }

  // --- TwiCC URL ---

  String get url => _prefs.getString(_keyUrl) ?? '';
  set url(String value) => _prefs.setString(_keyUrl, value);

  // --- Cloudflare Access JWT (secure storage) ---

  String? get cfJwt => _cfJwt;
  set cfJwt(String? value) {
    _cfJwt = value;
    if (value == null) {
      _secure.delete(key: _keyCfJwt);
    } else {
      _secure.write(key: _keyCfJwt, value: value);
    }
  }

  // --- Django session cookie (secure storage) ---

  String? get sessionCookie => _sessionCookie;
  set sessionCookie(String? value) {
    _sessionCookie = value;
    if (value == null) {
      _secure.delete(key: _keySessionCookie);
    } else {
      _secure.write(key: _keySessionCookie, value: value);
    }
  }

  // --- Self-signed TLS certificates ---

  bool get acceptSelfSignedCerts =>
      _prefs.getBool(_keyAcceptSelfSignedCerts) ?? false;
  set acceptSelfSignedCerts(bool value) =>
      _prefs.setBool(_keyAcceptSelfSignedCerts, value);

  // --- Sound notifications ---

  bool get soundEnabled => _prefs.getBool(_keySoundEnabled) ?? true;
  set soundEnabled(bool value) => _prefs.setBool(_keySoundEnabled, value);

  // --- Native notifications ---

  bool get notificationsEnabled => _prefs.getBool(_keyNotificationsEnabled) ?? true;
  set notificationsEnabled(bool value) => _prefs.setBool(_keyNotificationsEnabled, value);

  // --- Poll interval (seconds, 0 = realtime) ---

  int get pollInterval => _prefs.getInt(_keyPollInterval) ?? 0;
  set pollInterval(int value) => _prefs.setInt(_keyPollInterval, value);

  /// Available poll interval options with human-readable labels.
  static const List<({int seconds, String label})> pollIntervalOptions = [
    (seconds: 0, label: 'Realtime'),
    (seconds: 30, label: '30 seconds'),
    (seconds: 60, label: '1 minute'),
    (seconds: 300, label: '5 minutes'),
    (seconds: 900, label: '15 minutes'),
  ];

  // --- Auto-connect on launch ---

  bool get autoConnect => _prefs.getBool(_keyAutoConnect) ?? false;
  set autoConnect(bool value) => _prefs.setBool(_keyAutoConnect, value);

  // --- Audio alerts (media stream, bypasses DND) ---

  bool get audioAlertEnabled => _prefs.getBool(_keyAudioAlertEnabled) ?? false;
  set audioAlertEnabled(bool value) => _prefs.setBool(_keyAudioAlertEnabled, value);

  bool get audioAlertOnQuestion => _prefs.getBool(_keyAudioAlertOnQuestion) ?? true;
  set audioAlertOnQuestion(bool value) => _prefs.setBool(_keyAudioAlertOnQuestion, value);

  bool get audioAlertOnWaiting => _prefs.getBool(_keyAudioAlertOnWaiting) ?? true;
  set audioAlertOnWaiting(bool value) => _prefs.setBool(_keyAudioAlertOnWaiting, value);

  // --- WebSocket stats persistence ---

  String? get statsJson => _prefs.getString(_keyStatsBuckets);
  Future<void> setStatsJson(String json) => _prefs.setString(_keyStatsBuckets, json);
  Future<void> clearStatsJson() => _prefs.remove(_keyStatsBuckets);

  /// Whether a URL has been configured.
  bool get isConfigured => url.isNotEmpty;

  /// Build the WebSocket URL from the configured TwiCC URL.
  ///
  /// Converts `https://` to `wss://` and `http://` to `ws://`,
  /// then appends `/ws/`.
  String? get wsUrl {
    if (!isConfigured) return null;
    final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final wsBase = base
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return '$wsBase/ws/';
  }
}
