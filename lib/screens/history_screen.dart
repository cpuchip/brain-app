import 'package:flutter/material.dart';
import '../services/brain_api.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  final BrainApi api;

  const HistoryScreen({super.key, required this.api});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryEntry>? _entries;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final entries = await widget.api.getHistory(limit: 50);
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _buildBody(theme, colorScheme),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text('Failed to load history',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_error!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _loadHistory,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    final entries = _entries ?? [];
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: colorScheme.outline),
            const SizedBox(height: 12),
            Text('No history yet',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: colorScheme.outline)),
            const SizedBox(height: 4),
            Text('Send your first thought to get started',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.outline)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          return _HistoryCard(entry: entries[index]);
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;

  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('MMM d, h:mm a');

    final categoryColor = _categoryColor(entry.category, colorScheme);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: category badge + timestamp
            Row(
              children: [
                if (entry.category != null) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      entry.category!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: categoryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (entry.confidence != null)
                  Text(
                    '${(entry.confidence! * 100).toInt()}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                const Spacer(),
                Text(
                  dateFormat.format(entry.timestamp.toLocal()),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),

            // Title
            if (entry.title != null) ...[
              const SizedBox(height: 6),
              Text(
                entry.title!,
                style: theme.textTheme.titleSmall,
              ),
            ],

            // Text
            const SizedBox(height: 4),
            Text(
              entry.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.8),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),

            // Status
            if (!entry.processed) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.pending, size: 14, color: colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    'Pending classification',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _categoryColor(String? category, ColorScheme colorScheme) {
    return switch (category) {
      'insight' => Colors.amber.shade700,
      'question' => Colors.blue.shade600,
      'action' => Colors.green.shade600,
      'reflection' => Colors.purple.shade500,
      'connection' => Colors.teal.shade600,
      'inbox' => colorScheme.outline,
      _ => colorScheme.outline,
    };
  }
}
