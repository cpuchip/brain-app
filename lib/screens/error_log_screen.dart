import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/error_log_service.dart';

class ErrorLogScreen extends StatefulWidget {
  const ErrorLogScreen({super.key});

  @override
  State<ErrorLogScreen> createState() => _ErrorLogScreenState();
}

class _ErrorLogScreenState extends State<ErrorLogScreen> {
  final _log = ErrorLogService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _log.entries;

    return Scaffold(
      appBar: AppBar(
        title: Text('Error Log (${entries.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all',
            onPressed: entries.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _log.export()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear',
            onPressed: entries.isEmpty
                ? null
                : () {
                    _log.clear();
                    setState(() {});
                  },
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('No errors logged',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                  12, 8, 12, MediaQuery.of(context).viewPadding.bottom + 16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_sourceIcon(entry.source),
                              size: 14, color: theme.colorScheme.error),
                          const SizedBox(width: 6),
                          Text(
                            entry.source,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatTime(entry.timestamp),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.message,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  IconData _sourceIcon(String source) => switch (source) {
        'websocket' => Icons.sync_problem,
        'api' => Icons.cloud_off,
        'queue' => Icons.pending,
        'notification' => Icons.notifications_off,
        _ => Icons.error_outline,
      };
}
