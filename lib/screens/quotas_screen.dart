import 'dart:async';

import 'package:flutter/material.dart';

import '../models/usage_data.dart';
import '../services/quota_service.dart';

/// Screen displaying Claude usage quotas (5-hour and 7-day windows).
class QuotasScreen extends StatefulWidget {
  final QuotaService quotaService;

  const QuotasScreen({super.key, required this.quotaService});

  @override
  State<QuotasScreen> createState() => _QuotasScreenState();
}

class _QuotasScreenState extends State<QuotasScreen> {
  Timer? _refreshTimer;

  QuotaService get _quota => widget.quotaService;

  @override
  void initState() {
    super.initState();
    _quota.addListener(_onChanged);
    // Refresh every 15s to update time-remaining counters.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _quota.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_quota.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_quota.hasOauth) {
      return _buildNoOauth(context);
    }

    final usage = _quota.usage;
    if (usage == null) {
      return const Center(child: Text('No quota data available'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildQuotaCard(
          context,
          title: '5-Hour Window',
          utilization: usage.fiveHourUtilization,
          timeRemaining: usage.fiveHourTimeRemaining,
          temporalPct: usage.fiveHourTemporalPct,
          burnRate: usage.fiveHourBurnRate,
          cost: usage.fiveHourCost,
        ),
        const SizedBox(height: 12),
        _buildQuotaCard(
          context,
          title: '7-Day Window',
          utilization: usage.sevenDayUtilization,
          timeRemaining: usage.sevenDayTimeRemaining,
          temporalPct: usage.sevenDayTemporalPct,
          burnRate: usage.sevenDayBurnRate,
          cost: usage.sevenDayCost,
        ),
        // Per-model sub-quotas
        if (usage.sevenDayOpusUtilization != null) ...[
          const SizedBox(height: 12),
          _buildSubQuotaCard(
            context,
            title: '7-Day Opus',
            utilization: usage.sevenDayOpusUtilization!,
            resetsAt: usage.sevenDayOpusResetsAt,
          ),
        ],
        if (usage.sevenDaySonnetUtilization != null) ...[
          const SizedBox(height: 12),
          _buildSubQuotaCard(
            context,
            title: '7-Day Sonnet',
            utilization: usage.sevenDaySonnetUtilization!,
            resetsAt: usage.sevenDaySonnetResetsAt,
          ),
        ],
        if (usage.sevenDayOauthAppsUtilization != null) ...[
          const SizedBox(height: 12),
          _buildSubQuotaCard(
            context,
            title: '7-Day OAuth Apps',
            utilization: usage.sevenDayOauthAppsUtilization!,
            resetsAt: usage.sevenDayOauthAppsResetsAt,
          ),
        ],
        if (usage.sevenDayCoworkUtilization != null) ...[
          const SizedBox(height: 12),
          _buildSubQuotaCard(
            context,
            title: '7-Day Cowork',
            utilization: usage.sevenDayCoworkUtilization!,
            resetsAt: usage.sevenDayCoworkResetsAt,
          ),
        ],
        // Extra usage
        if (usage.extraUsageIsEnabled) ...[
          const SizedBox(height: 12),
          _buildExtraUsageCard(context, usage),
        ],
        // Last updated
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Last updated: ${_formatTime(usage.fetchedAt.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoOauth(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'OAuth not configured',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'TwiCC needs OAuth authentication with Anthropic to fetch usage quotas. '
              'Configure it in TwiCC settings.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotaCard(
    BuildContext context, {
    required String title,
    required double utilization,
    required Duration timeRemaining,
    required double temporalPct,
    required double? burnRate,
    required PeriodCost? cost,
  }) {
    final theme = Theme.of(context);
    final color = _utilizationColor(utilization);
    final pct = utilization.clamp(0, 100);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${utilization.toStringAsFixed(1)}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Usage bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  // Background
                  Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  // Temporal pace marker
                  if (temporalPct > 0)
                    Positioned(
                      left: _barFraction(temporalPct * 100, context) - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  // Usage fill
                  FractionallySizedBox(
                    widthFactor: (pct / 100).clamp(0.0, 1.0),
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Details row
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Resets in ${_formatDuration(timeRemaining)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (burnRate != null) ...[
                  const Spacer(),
                  _buildBurnRateChip(theme, burnRate),
                ],
              ],
            ),
            // Cost info
            if (cost != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.attach_money, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '\$${cost.spent.toStringAsFixed(2)} spent',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'est. \$${cost.estimatedMonthly.toStringAsFixed(0)}/mo',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (cost.capped) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.block, size: 14, color: theme.colorScheme.error),
                    const SizedBox(width: 2),
                    Text(
                      'Capped',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSubQuotaCard(
    BuildContext context, {
    required String title,
    required double utilization,
    required DateTime? resetsAt,
  }) {
    final theme = Theme.of(context);
    final color = _utilizationColor(utilization);
    final pct = utilization.clamp(0, 100);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '${utilization.toStringAsFixed(1)}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: color,
                minHeight: 8,
              ),
            ),
            if (resetsAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Resets in ${_formatDuration(resetsAt.difference(DateTime.now()))}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExtraUsageCard(BuildContext context, UsageData usage) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Extra Usage', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (usage.extraUsageUtilization != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (usage.extraUsageUtilization! / 100).clamp(0.0, 1.0),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: _utilizationColor(usage.extraUsageUtilization!),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                if (usage.extraUsageUsedCredits != null)
                  Text(
                    '\$${usage.extraUsageUsedCredits!.toStringAsFixed(2)} used',
                    style: theme.textTheme.bodySmall,
                  ),
                if (usage.extraUsageMonthlyLimit != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'of \$${(usage.extraUsageMonthlyLimit! / 100).toStringAsFixed(0)} limit',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBurnRateChip(ThemeData theme, double burnRate) {
    final (icon, color, label) = switch (burnRate) {
      < 0.5 => (Icons.trending_down, Colors.green, 'Slow'),
      < 0.8 => (Icons.trending_flat, theme.colorScheme.onSurfaceVariant, 'Steady'),
      <= 1.0 => (Icons.trending_up, Colors.orange, 'On pace'),
      _ => (Icons.trending_up, Colors.red, 'Fast'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(
          '$label (${burnRate.toStringAsFixed(1)}x)',
          style: theme.textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }

  /// Get the color for a utilization percentage.
  Color _utilizationColor(double utilization) {
    if (utilization >= 80) return Colors.red;
    if (utilization >= 50) return Colors.orange;
    return Colors.green;
  }

  /// Compute the pixel position for a percentage on the usage bar.
  double _barFraction(double pct, BuildContext context) {
    // Card padding (16*2) + some buffer
    final barWidth = MediaQuery.of(context).size.width - 64;
    return (pct / 100).clamp(0.0, 1.0) * barWidth;
  }

  /// Format a Duration as a human-readable string.
  String _formatDuration(Duration d) {
    if (d.isNegative) return 'expired';
    if (d.inDays > 0) {
      final hours = d.inHours % 24;
      return '${d.inDays}d ${hours}h';
    }
    if (d.inHours > 0) {
      final minutes = d.inMinutes % 60;
      return '${d.inHours}h ${minutes}m';
    }
    return '${d.inMinutes}m';
  }

  /// Format a DateTime as HH:MM:SS.
  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}
