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

  Future<void> _toggleDone(HistoryEntry entry) async {
    try {
      await widget.api.toggleDone(entry);
      await _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(entry.isDone ? 'Reopened' : 'Done!'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteEntry(HistoryEntry entry) async {
    try {
      await widget.api.deleteEntry(entry.id);
      await _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${entry.title ?? 'entry'}"'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.api.hasBrainUrl ? 'Brain' : 'History'),
        actions: [
          if (widget.api.hasBrainUrl)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: Icon(Icons.wifi, size: 14, color: Colors.green.shade600),
                label: const Text('Direct'),
                visualDensity: VisualDensity.compact,
              ),
            ),
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
          final entry = entries[index];
          final canManage = widget.api.hasBrainUrl;

          if (!canManage) {
            return _HistoryCard(entry: entry);
          }

          // With brain URL: swipe to delete
          return Dismissible(
            key: Key(entry.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete entry?'),
                  content: Text(entry.title ?? entry.text),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ) ?? false;
            },
            onDismissed: (_) => _deleteEntry(entry),
            child: _HistoryCard(
              entry: entry,
              onToggleDone: entry.isActionable ? () => _toggleDone(entry) : null,
            ),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback? onToggleDone;

  const _HistoryCard({required this.entry, this.onToggleDone});

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
            // Header: category badge + status + timestamp
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
                if (entry.status != null && entry.status!.isNotEmpty) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      entry.status!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.amber.shade700,
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
                if (entry.dueDate != null && entry.dueDate!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '📅 ${entry.dueDate}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.amber.shade700,
                      ),
                    ),
                  ),
                Text(
                  dateFormat.format(entry.timestamp.toLocal()),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),

            // Title with done indicator
            if (entry.title != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (onToggleDone != null)
                    GestureDetector(
                      onTap: onToggleDone,
                      child: Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: entry.isDone ? Colors.green.shade600 : Colors.transparent,
                          border: Border.all(
                            color: entry.isDone
                                ? Colors.green.shade600
                                : colorScheme.outline,
                            width: 2,
                          ),
                        ),
                        child: entry.isDone
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      entry.title!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        decoration: entry.isDone ? TextDecoration.lineThrough : null,
                        color: entry.isDone ? colorScheme.outline : null,
                      ),
                    ),
                  ),
                ],
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
      'actions' => Colors.green.shade600,
      'projects' => Colors.blue.shade600,
      'ideas' => Colors.purple.shade500,
      'people' => Colors.teal.shade600,
      'study' => Colors.amber.shade700,
      'journal' => Colors.pink.shade400,
      'inbox' => colorScheme.outline,
      // Legacy categories from relay
      'insight' => Colors.amber.shade700,
      'question' => Colors.blue.shade600,
      'action' => Colors.green.shade600,
      'reflection' => Colors.purple.shade500,
      'connection' => Colors.teal.shade600,
      _ => colorScheme.outline,
    };
  }
}
