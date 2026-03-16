/// Data model for Claude usage quota snapshots received via WebSocket.
class UsageData {
  final DateTime fetchedAt;

  // 5-hour window
  final double fiveHourUtilization;
  final DateTime fiveHourResetsAt;

  // 7-day global
  final double sevenDayUtilization;
  final DateTime sevenDayResetsAt;

  // 7-day per-model (nullable — null means no limit)
  final double? sevenDayOpusUtilization;
  final DateTime? sevenDayOpusResetsAt;
  final double? sevenDaySonnetUtilization;
  final DateTime? sevenDaySonnetResetsAt;
  final double? sevenDayOauthAppsUtilization;
  final DateTime? sevenDayOauthAppsResetsAt;
  final double? sevenDayCoworkUtilization;
  final DateTime? sevenDayCoworkResetsAt;

  // Extra usage
  final bool extraUsageIsEnabled;
  final double? extraUsageMonthlyLimit;
  final double? extraUsageUsedCredits;
  final double? extraUsageUtilization;

  // Period costs
  final PeriodCost? fiveHourCost;
  final PeriodCost? sevenDayCost;

  UsageData({
    required this.fetchedAt,
    required this.fiveHourUtilization,
    required this.fiveHourResetsAt,
    required this.sevenDayUtilization,
    required this.sevenDayResetsAt,
    this.sevenDayOpusUtilization,
    this.sevenDayOpusResetsAt,
    this.sevenDaySonnetUtilization,
    this.sevenDaySonnetResetsAt,
    this.sevenDayOauthAppsUtilization,
    this.sevenDayOauthAppsResetsAt,
    this.sevenDayCoworkUtilization,
    this.sevenDayCoworkResetsAt,
    this.extraUsageIsEnabled = false,
    this.extraUsageMonthlyLimit,
    this.extraUsageUsedCredits,
    this.extraUsageUtilization,
    this.fiveHourCost,
    this.sevenDayCost,
  });

  factory UsageData.fromJson(Map<String, dynamic> json) {
    final costs = json['period_costs'] as Map<String, dynamic>?;

    return UsageData(
      fetchedAt: DateTime.parse(json['fetched_at'] as String),
      fiveHourUtilization: (json['five_hour_utilization'] as num).toDouble(),
      fiveHourResetsAt: DateTime.parse(json['five_hour_resets_at'] as String),
      sevenDayUtilization: (json['seven_day_utilization'] as num).toDouble(),
      sevenDayResetsAt: DateTime.parse(json['seven_day_resets_at'] as String),
      sevenDayOpusUtilization: (json['seven_day_opus_utilization'] as num?)?.toDouble(),
      sevenDayOpusResetsAt: _tryParseDate(json['seven_day_opus_resets_at']),
      sevenDaySonnetUtilization: (json['seven_day_sonnet_utilization'] as num?)?.toDouble(),
      sevenDaySonnetResetsAt: _tryParseDate(json['seven_day_sonnet_resets_at']),
      sevenDayOauthAppsUtilization: (json['seven_day_oauth_apps_utilization'] as num?)?.toDouble(),
      sevenDayOauthAppsResetsAt: _tryParseDate(json['seven_day_oauth_apps_resets_at']),
      sevenDayCoworkUtilization: (json['seven_day_cowork_utilization'] as num?)?.toDouble(),
      sevenDayCoworkResetsAt: _tryParseDate(json['seven_day_cowork_resets_at']),
      extraUsageIsEnabled: json['extra_usage_is_enabled'] as bool? ?? false,
      extraUsageMonthlyLimit: (json['extra_usage_monthly_limit'] as num?)?.toDouble(),
      extraUsageUsedCredits: (json['extra_usage_used_credits'] as num?)?.toDouble(),
      extraUsageUtilization: (json['extra_usage_utilization'] as num?)?.toDouble(),
      fiveHourCost: costs?['five_hour'] != null
          ? PeriodCost.fromJson(costs!['five_hour'] as Map<String, dynamic>)
          : null,
      sevenDayCost: costs?['seven_day'] != null
          ? PeriodCost.fromJson(costs!['seven_day'] as Map<String, dynamic>)
          : null,
    );
  }

  static DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.parse(value as String);
  }

  /// Time remaining until the 5-hour window resets.
  Duration get fiveHourTimeRemaining => fiveHourResetsAt.difference(DateTime.now());

  /// Time remaining until the 7-day window resets.
  Duration get sevenDayTimeRemaining => sevenDayResetsAt.difference(DateTime.now());

  /// Fraction of the 5-hour window that has elapsed (0.0 to 1.0).
  double get fiveHourTemporalPct {
    const windowDuration = Duration(hours: 5);
    final remaining = fiveHourTimeRemaining;
    if (remaining.isNegative) return 1.0;
    return 1.0 - (remaining.inSeconds / windowDuration.inSeconds).clamp(0.0, 1.0);
  }

  /// Fraction of the 7-day window that has elapsed (0.0 to 1.0).
  double get sevenDayTemporalPct {
    const windowDuration = Duration(days: 7);
    final remaining = sevenDayTimeRemaining;
    if (remaining.isNegative) return 1.0;
    return 1.0 - (remaining.inSeconds / windowDuration.inSeconds).clamp(0.0, 1.0);
  }

  /// Burn rate for the 5-hour window (utilization / temporal%).
  /// A value > 1.0 means usage is ahead of the linear pace.
  double? get fiveHourBurnRate {
    final t = fiveHourTemporalPct;
    if (t < 0.001) return null; // Too early to compute
    return fiveHourUtilization / (t * 100);
  }

  /// Burn rate for the 7-day window.
  double? get sevenDayBurnRate {
    final t = sevenDayTemporalPct;
    if (t < 0.001) return null;
    return sevenDayUtilization / (t * 100);
  }
}

/// Cost data for a usage period.
class PeriodCost {
  final double spent;
  final double estimatedPeriod;
  final double estimatedMonthly;
  final bool capped;
  final DateTime? cutoffAt;

  PeriodCost({
    required this.spent,
    required this.estimatedPeriod,
    required this.estimatedMonthly,
    required this.capped,
    this.cutoffAt,
  });

  factory PeriodCost.fromJson(Map<String, dynamic> json) {
    return PeriodCost(
      spent: (json['spent'] as num).toDouble(),
      estimatedPeriod: (json['estimated_period'] as num).toDouble(),
      estimatedMonthly: (json['estimated_monthly'] as num).toDouble(),
      capped: json['capped'] as bool? ?? false,
      cutoffAt: json['cutoff_at'] != null ? DateTime.parse(json['cutoff_at'] as String) : null,
    );
  }
}
