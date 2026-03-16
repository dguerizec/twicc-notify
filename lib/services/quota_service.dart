import 'package:flutter/foundation.dart';

import '../models/usage_data.dart';

/// Holds the latest Claude usage quota data received via WebSocket.
///
/// Parses `usage_updated` messages and notifies listeners when data changes.
class QuotaService extends ChangeNotifier {
  UsageData? _usage;
  bool _hasOauth = false;
  bool _isLoading = true;

  UsageData? get usage => _usage;
  bool get hasOauth => _hasOauth;
  bool get isLoading => _isLoading;

  /// Process an incoming `usage_updated` WebSocket message.
  void handleUsageUpdated(Map<String, dynamic> json) {
    final success = json['success'] as bool? ?? false;
    _hasOauth = json['has_oauth'] as bool? ?? false;

    if (success && json['usage'] != null) {
      try {
        _usage = UsageData.fromJson(json['usage'] as Map<String, dynamic>);
      } catch (e) {
        debugPrint('[TwiCC] Failed to parse usage data: $e');
      }
    }

    _isLoading = false;
    notifyListeners();
  }
}
