import 'dart:async';

import 'package:flutter/material.dart';

import '../models/stats_bucket.dart';
import '../services/stats_service.dart';
import '../services/websocket_service.dart';
import '../utils/format.dart';

/// Screen displaying WebSocket message statistics.
///
/// Shows total messages and bytes exchanged, broken down by
/// time window (last hour, 24 hours, 7 days, 30 days).
class StatsScreen extends StatefulWidget {
  final StatsService statsService;
  final WebSocketService wsService;

  const StatsScreen({
    super.key,
    required this.statsService,
    required this.wsService,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Timer? _refreshTimer;

  StatsService get _stats => widget.statsService;
  WebSocketService get _ws => widget.wsService;

  @override
  void initState() {
    super.initState();
    _stats.addListener(_onStatsChanged);
    _ws.addListener(_onStatsChanged);
    // Refresh every 5 seconds to update time-based window boundaries.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _stats.removeListener(_onStatsChanged);
    _ws.removeListener(_onStatsChanged);
    super.dispose();
  }

  void _onStatsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final windows = _stats.getAllWindows();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildConnectionChip(theme),
        const SizedBox(height: 16),
        _buildSummaryCard(theme, windows),
        const SizedBox(height: 16),
        _buildWindowsCard(theme, windows),
        const SizedBox(height: 24),
        _buildResetButton(theme),
      ],
    );
  }

  Widget _buildConnectionChip(ThemeData theme) {
    final (color, label) = switch (_ws.state) {
      WsConnectionState.connected => (Colors.green, 'Connected'),
      WsConnectionState.connecting => (Colors.orange, 'Connecting…'),
      WsConnectionState.authRequired => (Colors.red, 'Auth required'),
      WsConnectionState.error => (Colors.red, 'Error'),
      WsConnectionState.disconnected => (Colors.grey, 'Disconnected'),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        avatar: Icon(Icons.circle, size: 10, color: color),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme,
    Map<String, StatsAggregate> windows,
  ) {
    // Use the 30-day window as the "total" (we only keep 31 days of data).
    final total = windows['Last 30 days']!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    icon: Icons.message_outlined,
                    label: 'Messages',
                    value: formatNumber(total.totalMessages),
                    detail:
                        '${formatNumber(total.messagesSent)} sent · ${formatNumber(total.messagesReceived)} received',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _SummaryTile(
                    icon: Icons.data_usage_outlined,
                    label: 'Data',
                    value: formatBytes(total.totalBytes),
                    detail:
                        '${formatBytes(total.bytesSent)} sent · ${formatBytes(total.bytesReceived)} received',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowsCard(
    ThemeData theme,
    Map<String, StatsAggregate> windows,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Breakdown', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1.5),
                2: FlexColumnWidth(1.5),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor,
                        width: 1,
                      ),
                    ),
                  ),
                  children: [
                    _headerCell('Window', theme),
                    _headerCell('Messages', theme, align: TextAlign.right),
                    _headerCell('Data', theme, align: TextAlign.right),
                  ],
                ),
                for (final entry in windows.entries)
                  _buildWindowRow(entry.key, entry.value, theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TableRow _buildWindowRow(
    String label,
    StatsAggregate stats,
    ThemeData theme,
  ) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            formatNumber(stats.totalMessages),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            formatBytes(stats.totalBytes),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String text, ThemeData theme, {TextAlign? align}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        textAlign: align,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildResetButton(ThemeData theme) {
    return Center(
      child: TextButton.icon(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Reset statistics?'),
              content: const Text('This will clear all recorded stats. This cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Reset'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await _stats.reset();
          }
        },
        icon: const Icon(Icons.delete_outline),
        label: const Text('Reset Stats'),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;

  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
