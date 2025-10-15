import 'package:flutter/material.dart';

import '../models/log_entry.dart';

class LogEntryTile extends StatelessWidget {
  const LogEntryTile({super.key, required this.entry, required this.isEven});

  final LogEntry entry;
  final bool isEven;

  Color _zebraColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surface;
    final alternate = Color.alphaBlend(
      scheme.primary.withOpacity(0.04),
      scheme.surface,
    );
    return isEven ? base : alternate;
  }

  Color _accentForSeverity() {
    switch (entry.severity) {
      case LogSeverity.emergency:
      case LogSeverity.alert:
      case LogSeverity.critical:
        return Colors.red.shade400;
      case LogSeverity.error:
        return Colors.red.shade300;
      case LogSeverity.warning:
        return Colors.orange.shade400;
      case LogSeverity.notice:
        return Colors.blueGrey.shade400;
      case LogSeverity.info:
        return Colors.blue.shade400;
      case LogSeverity.debug:
        return Colors.green.shade400;
    }
  }

  IconData _iconForSeverity() {
    switch (entry.severity) {
      case LogSeverity.emergency:
      case LogSeverity.alert:
      case LogSeverity.critical:
        return Icons.error_outline;
      case LogSeverity.error:
        return Icons.error_outline;
      case LogSeverity.warning:
        return Icons.warning_amber_outlined;
      case LogSeverity.notice:
        return Icons.info_outline;
      case LogSeverity.info:
        return Icons.info_outline;
      case LogSeverity.debug:
        return Icons.bug_report_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentForSeverity();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _zebraColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _iconForSeverity(),
            color: accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Timestamp',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.formattedTimestamp,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Realtime timestamp',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.formattedRealtimeTimestamp,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  entry.message,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
