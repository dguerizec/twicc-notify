import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/process_state.dart';
import '../utils/preferences.dart';
import 'audio_alert_service.dart';

/// Notification channel ID. Bump the version suffix if you need to
/// force-recreate the channel with new settings (Android locks channel
/// settings after first creation).
const _notificationChannelId = 'twicc_claude_v2';

/// Manages native notification display, deep-linking, and audio alerts.
///
/// Distinguishes two types of events:
/// - **Question** (`pending_request`): Claude is asking a question or needs
///   permission during `assistant_turn`. More urgent — Claude is blocked.
/// - **Waiting** (`user_turn`): Claude finished its turn and is waiting for
///   a new prompt. Less urgent — informational.
///
/// Each event type has its own notification message and audio alert sound.
class NotificationService {
  final AppPreferences _prefs;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  late final AudioAlertService _audioAlerts;

  /// Track which sessions we've already notified about to avoid duplicates.
  /// Cleared when a session no longer needs attention.
  final Set<String> _notifiedSessions = {};

  /// The deep-link URL from the most recent notification.
  String? _lastNotifiedUrl;

  /// Returns the last notified deep-link URL, or the TwiCC home URL.
  String get lastUrlOrHome => _lastNotifiedUrl ?? _prefs.url;

  NotificationService(this._prefs) {
    _audioAlerts = AudioAlertService(_prefs);
  }

  /// Initialize the notification plugin with platform-specific settings.
  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      macOS: darwinSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Request notification permissions on Android 13+
    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
        // Pre-create the notification channel with explicit sound/vibration settings.
        // Once created, Android locks these settings — they can only be changed by
        // the user in system settings. Using a versioned ID forces recreation.
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _notificationChannelId,
            'Claude Notifications',
            description: 'Notifications when Claude needs your attention',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
            enableLights: true,
          ),
        );
      }
    }
  }

  /// Handle a process state change. Shows a notification if the process
  /// needs user attention and we haven't already notified for it.
  /// Differentiates between question/permission (pending_request) and
  /// waiting for new prompt (user_turn).
  Future<void> handleProcessState(ProcessStateInfo info) async {
    if (info.needsAttention) {
      if (_notifiedSessions.add(info.sessionId)) {
        final isQuestion = info.pendingRequest != null;
        debugPrint('[TwiCC] Notifying (${isQuestion ? 'question' : 'waiting'}): '
            'session=${info.sessionId.substring(0, 12)}…');
        await _showNotification(info, isQuestion: isQuestion);
        await _audioAlerts.play(isQuestion ? AlertSound.question : AlertSound.waiting);
      }
    } else {
      // Process no longer needs attention — clear the notification tracker
      _notifiedSessions.remove(info.sessionId);
    }
  }

  /// Handle the `active_processes` message on connection.
  /// Notifies for any processes that need user attention.
  Future<void> handleActiveProcesses(List<ProcessStateInfo> processes) async {
    for (final process in processes) {
      if (process.needsAttention && _notifiedSessions.add(process.sessionId)) {
        final isQuestion = process.pendingRequest != null;
        debugPrint('[TwiCC] Notifying (${isQuestion ? 'question' : 'waiting'}): '
            'session=${process.sessionId.substring(0, 12)}…');
        await _showNotification(process, isQuestion: isQuestion);
        await _audioAlerts.play(isQuestion ? AlertSound.question : AlertSound.waiting);
      }
    }
  }

  /// Show a native notification for a process that needs attention.
  ///
  /// [isQuestion] controls the notification title/body:
  /// - `true`: "Claude has a question" (pending_request — urgent)
  /// - `false`: "Claude finished its turn" (user_turn — informational)
  Future<void> _showNotification(ProcessStateInfo info, {required bool isQuestion}) async {
    if (!_prefs.notificationsEnabled) return;

    final projectName = info.projectName ?? 'Unknown project';
    final sessionTitle = info.sessionTitle ?? 'Untitled session';
    final deepLink = info.deepLinkUrl(_prefs.url);
    _lastNotifiedUrl = deepLink;

    final title = isQuestion ? 'Claude has a question' : 'Claude finished its turn';

    final androidDetails = AndroidNotificationDetails(
      _notificationChannelId,
      'Claude Notifications',
      channelDescription: 'Notifications when Claude needs your attention',
      importance: Importance.high,
      priority: Priority.high,
      playSound: _prefs.soundEnabled,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      macOS: darwinDetails,
    );

    // Use a hash of the session ID as the notification ID
    // so we can update/replace notifications for the same session.
    final notificationId = info.sessionId.hashCode;

    await _notifications.show(
      notificationId,
      title,
      '$projectName — $sessionTitle',
      details,
      payload: deepLink,
    );
  }

  /// Called when the user taps a notification.
  /// Opens Chrome/default browser to the session's deep-link URL.
  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _openUrl(payload);
    }
  }

  /// Open a URL in the default browser.
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  /// Clear all tracked notification state.
  void reset() {
    _notifiedSessions.clear();
  }

  /// Release resources.
  void dispose() {
    _audioAlerts.dispose();
  }
}
