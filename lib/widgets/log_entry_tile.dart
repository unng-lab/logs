import 'package:flutter/material.dart';

import '../models/log_entry.dart';

class LogEntryTile extends StatelessWidget {
  const LogEntryTile({super.key, required this.entry});

  final LogEntry entry;

  Color _colorForSeverity(BuildContext context) {
    switch (entry.severity) {
      case LogSeverity.emergency:
      case LogSeverity.alert:
      case LogSeverity.critical:
        return Colors.red.shade300;
      case LogSeverity.error:
        return Colors.red.shade200;
      case LogSeverity.warning:
        return Colors.orange.shade200;
      case LogSeverity.notice:
        return Colors.blueGrey.shade200;
      case LogSeverity.info:
        return Theme.of(context).colorScheme.surfaceVariant;
      case LogSeverity.debug:
        return Theme.of(context).colorScheme.surface;
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
    return Card(
      color: _colorForSeverity(context),
      child: ListTile(
        leading: Icon(_iconForSeverity()),
        title: Text(
          entry.message,
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(entry.formattedTimestamp),
        dense: true,
        isThreeLine: true,
      ),
    );
  }
}
