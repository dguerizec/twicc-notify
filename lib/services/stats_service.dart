import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/stats_bucket.dart';
import '../utils/preferences.dart';

/// Tracks WebSocket message statistics in 5-minute buckets.
///
/// Records sent/received message counts and byte sizes, persists to
/// SharedPreferences, and exposes aggregated stats over time windows.
class StatsService extends ChangeNotifier {
  static const _bucketSizeSeconds = 300; // 5 minutes
  static const _maxAgeSeconds = 31 * 24 * 3600; // 31 days

  final AppPreferences _prefs;
  List<StatsBucket> _buckets = [];
  int _recordCount = 0;

  StatsService(this._prefs);

  /// Load persisted stats from SharedPreferences.
  Future<void> init() async {
    final json = _prefs.statsJson;
    if (json != null) {
      try {
        final list = jsonDecode(json) as List<dynamic>;
        _buckets = list
            .map((e) => StatsBucket.fromJson(e as Map<String, dynamic>))
            .toList();
        _prune();
      } catch (e) {
        debugPrint('[TwiCC Stats] Failed to load stats: $e');
        _buckets = [];
      }
    }
  }

  /// Record a sent message (including pings).
  void recordSent(int bytes) {
    final bucket = _currentBucket();
    bucket.messagesSent++;
    bucket.bytesSent += bytes;
    _onRecord();
  }

  /// Record a received message (including pongs).
  void recordReceived(int bytes) {
    final bucket = _currentBucket();
    bucket.messagesReceived++;
    bucket.bytesReceived += bytes;
    _onRecord();
  }

  /// Get aggregated stats for a time window.
  StatsAggregate getStats(Duration window) {
    final cutoff = _nowSeconds() - window.inSeconds;
    var messagesSent = 0;
    var messagesReceived = 0;
    var bytesSent = 0;
    var bytesReceived = 0;

    for (final bucket in _buckets) {
      if (bucket.timestamp >= cutoff) {
        messagesSent += bucket.messagesSent;
        messagesReceived += bucket.messagesReceived;
        bytesSent += bucket.bytesSent;
        bytesReceived += bucket.bytesReceived;
      }
    }

    return StatsAggregate(
      messagesSent: messagesSent,
      messagesReceived: messagesReceived,
      bytesSent: bytesSent,
      bytesReceived: bytesReceived,
    );
  }

  /// Get stats for all predefined time windows.
  Map<String, StatsAggregate> getAllWindows() => {
        'Last hour': getStats(const Duration(hours: 1)),
        'Last 24 hours': getStats(const Duration(hours: 24)),
        'Last 7 days': getStats(const Duration(days: 7)),
        'Last 30 days': getStats(const Duration(days: 30)),
      };

  /// Clear all stats and persist.
  Future<void> reset() async {
    _buckets.clear();
    _recordCount = 0;
    await _prefs.clearStatsJson();
    notifyListeners();
  }

  /// Get or create the current 5-minute bucket.
  StatsBucket _currentBucket() {
    final now = _nowSeconds();
    final bucketTime = now - (now % _bucketSizeSeconds);

    if (_buckets.isNotEmpty && _buckets.last.timestamp == bucketTime) {
      return _buckets.last;
    }

    final bucket = StatsBucket(timestamp: bucketTime);
    _buckets.add(bucket);
    return bucket;
  }

  /// Common logic after each recording.
  void _onRecord() {
    _recordCount++;
    // Prune and persist every 50 records to avoid excessive I/O.
    if (_recordCount % 50 == 0) {
      _prune();
    }
    _persist();
    notifyListeners();
  }

  /// Remove buckets older than 31 days.
  void _prune() {
    final cutoff = _nowSeconds() - _maxAgeSeconds;
    _buckets.removeWhere((b) => b.timestamp < cutoff);
  }

  /// Persist current buckets to SharedPreferences.
  void _persist() {
    final json = jsonEncode(_buckets.map((b) => b.toJson()).toList());
    _prefs.setStatsJson(json);
  }

  int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
