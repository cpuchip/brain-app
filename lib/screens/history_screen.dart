import 'package:flutter/material.dart';
import 'dart:async';
import '../services/brain_api.dart';
import '../services/brain_service.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import 'edit_entry_screen.dart';
import 'create_entry_screen.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  final BrainApi api;
  final Stream<EntryUpdatedEvent>? entryUpdated;
  final bool embedded;

  const HistoryScreen({super.key, required this.api, this.entryUpdated, this.embedded = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryEntry>? _entries;
  String? _error;
  bool _loading = true;
  bool _isStale = false;
  DateTime? _cachedAt;

  // Search & filter state
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _categoryFilter;
  bool _showArchived = false;
  bool _showDone = false;
  Timer? _debounce;
  StreamSubscription<EntryUpdatedEvent>? _entryUpdatedSub;

  static const _filterCategories = [
    'actions', 'projects', 'ideas', 'people', 'study', 'journal', 'inbox',
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _entryUpdatedSub = widget.entryUpdated?.listen(_onEntryUpdated);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _entryUpdatedSub?.cancel();
    super.dispose();
  }

  void _onEntryUpdated(EntryUpdatedEvent event) {
    final entries = _entries;
    if (entries == null) return;

    final idx = entries.indexWhere((e) => e.id == event.id);
    final updated = HistoryEntry(
      id: event.id,
      text: event.body,
      category: event.category,
      title: event.title,
      confidence: null,
      timestamp: DateTime.tryParse(event.createdAt) ?? DateTime.now(),
      processed: true,
      actionDone: event.actionDone,
      status: event.status,
      dueDate: event.dueDate,
      nextAction: event.nextAction,
      tags: event.tags,
      subtasks: event.subtasks.map((e) => SubTask.fromJson(e)).toList(),
    );

    setState(() {
      if (idx >= 0) {
        entries[idx] = updated;
      } else {
        entries.insert(0, updated);
      }
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _searchQuery = query.toLowerCase());
    });
  }

  List<HistoryEntry> get _filteredEntries {
    final entries = _entries ?? [];
    return entries.where((e) {
      // Category filter
      if (_categoryFilter != null && e.category != _categoryFilter) return false;
      // Archive filter: hide archived unless showing archived
      if (!_showArchived && e.status == 'archived') return false;
      if (_showArchived && e.status != 'archived') return false;
      // Done filter
      if (_showDone && !e.isDone) return false;
      // Text search
      if (_searchQuery.isNotEmpty) {
        final haystack = '${e.title ?? ''} ${e.text} ${e.tags.join(' ')} ${e.nextAction ?? ''}'.toLowerCase();
        if (!haystack.contains(_searchQuery)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.api.getHistory(limit: 50);
      if (mounted) {
        setState(() {
          _entries = result.entries;
          _isStale = result.isStale;
          _cachedAt = result.cachedAt;
          _loading = false;
        });
      }
      // Rebuild notification reminders and update widget
      NotificationService().rebuildReminders(result.entries);
      WidgetService().updateWidget(result.entries);
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
    // Optimistic remove from local list
    final entries = _entries;
    if (entries == null) return;
    final idx = entries.indexOf(entry);
    setState(() => entries.remove(entry));

    // Show undo toast — actual delete fires after toast expires
    bool undone = false;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${entry.title ?? 'entry'}"'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            undone = true;
            setState(() {
              if (idx >= 0 && idx <= (entries.length)) {
                entries.insert(idx, entry);
              } else {
                entries.insert(0, entry);
              }
            });
          },
        ),
      ),
    ).closed.then((_) async {
      if (undone) return;
      // Toast expired without undo — actually delete
      try {
        await widget.api.deleteEntry(entry.id);
      } catch (e) {
        // Delete failed — re-insert
        if (mounted) {
          setState(() => entries.insert(0, entry));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Delete failed: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });
  }

  Future<void> _editEntry(HistoryEntry entry) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditEntryScreen(
          api: widget.api,
          entry: entry,
          entryUpdated: widget.entryUpdated,
        ),
      ),
    );
    if (changed == true) {
      await _loadHistory();
    }
  }

  Future<void> _archiveEntry(HistoryEntry entry) async {
    try {
      await widget.api.archiveEntry(entry.id);
      await _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archived "${entry.title ?? 'entry'}"'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                await widget.api.updateEntry(entry.id, {'status': entry.status ?? 'active'});
                await _loadHistory();
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archive failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _createEntry() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateEntryScreen(api: widget.api),
      ),
    );
    if (created == true) {
      await _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final body = Column(
      children: [
        // Offline banner
        if (_isStale)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.amber.shade100,
            child: Row(
              children: [
                Icon(Icons.cloud_off, size: 16, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _cachedAt != null
                        ? 'Offline — showing cached data from ${DateFormat('MMM d, h:mm a').format(_cachedAt!)}'
                        : 'Offline — showing cached data',
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                  ),
                ),
                InkWell(
                  onTap: _loadHistory,
                  child: Icon(Icons.refresh, size: 16, color: Colors.amber.shade800),
                ),
              ],
            ),
          ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search entries...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ),

        // Filter chips
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              FilterChip(
                label: const Text('Done'),
                selected: _showDone,
                onSelected: (v) => setState(() => _showDone = v),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              ..._filterCategories.map((cat) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(cat),
                  selected: _categoryFilter == cat,
                  onSelected: (v) => setState(() => _categoryFilter = v ? cat : null),
                  visualDensity: VisualDensity.compact,
                ),
              )),
            ],
          ),
        ),

        // Entry list
        Expanded(child: _buildBody(theme, colorScheme)),
      ],
    );

    if (widget.embedded) {
      return Stack(
        children: [
          body,
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _createEntry,
              tooltip: 'New entry',
              child: const Icon(Icons.add),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Brain'),
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
            icon: Icon(_showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined),
            tooltip: _showArchived ? 'Show active' : 'Show archived',
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadHistory,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createEntry,
        tooltip: 'New entry',
        child: const Icon(Icons.add),
      ),
      body: body,
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

    final entries = _filteredEntries;
    if (entries.isEmpty) {
      final hasFilters = _searchQuery.isNotEmpty || _categoryFilter != null || _showDone || _showArchived;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilters ? Icons.filter_list_off : Icons.inbox_outlined,
              size: 64,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              hasFilters ? 'No matching entries' : 'No history yet',
              style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.outline),
            ),
            const SizedBox(height: 4),
            Text(
              hasFilters ? 'Try adjusting your filters' : 'Send your first thought to get started',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                  _categoryFilter = null;
                  _showDone = false;
                  _showArchived = false;
                }),
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewPadding.bottom + 80),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final entry = entries[index];

          // Swipe to delete (left) or archive (right), toggle done for actionable
          return Dismissible(
            key: Key(entry.id),
            direction: _showArchived
                ? DismissDirection.endToStart  // archived view: only delete
                : DismissDirection.horizontal, // normal view: both directions
            background: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20),
              decoration: BoxDecoration(
                color: Colors.amber.shade700,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.archive, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Archive', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            secondaryBackground: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                // Archive: no confirmation needed (has undo)
                return true;
              }
              // Delete: confirm
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
            onDismissed: (direction) {
              if (direction == DismissDirection.startToEnd) {
                _archiveEntry(entry);
              } else {
                _deleteEntry(entry);
              }
            },
            child: _HistoryCard(
              entry: entry,
              onToggleDone: () => _toggleDone(entry),
              onTap: () => _editEntry(entry),
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
  final VoidCallback? onTap;

  const _HistoryCard({required this.entry, this.onToggleDone, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('MMM d, h:mm a');

    final categoryColor = _categoryColor(entry.category, colorScheme);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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

            // Text (strip markdown for preview)
            const SizedBox(height: 4),
            Text(
              _stripMarkdown(entry.text),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.8),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),

            // Next action
            if (entry.nextAction != null && entry.nextAction!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.arrow_forward, size: 14, color: Colors.blue.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      entry.nextAction!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.blue.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // Tags
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: entry.tags.map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.outline.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tag,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                )).toList(),
              ),
            ],

            // Sub-task progress
            if (entry.subtasks.isNotEmpty) ...[
              const SizedBox(height: 6),
              () {
                final done = entry.subtasks.where((s) => s.done).length;
                final total = entry.subtasks.length;
                return Row(
                  children: [
                    Icon(Icons.checklist, size: 14, color: done == total ? Colors.green.shade600 : colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(
                      '$done/$total',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: done == total ? Colors.green.shade600 : colorScheme.outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total > 0 ? done / total : 0,
                          minHeight: 4,
                          backgroundColor: colorScheme.outline.withValues(alpha: 0.15),
                          color: done == total ? Colors.green.shade600 : colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                );
              }(),
            ],

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
      ),
    );
  }

  /// Strip common markdown syntax for plain-text preview in list cards.
  static String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '') // headings
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')          // bold
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1')               // italic
        .replaceAll(RegExp(r'~~(.+?)~~'), r'$1')               // strikethrough
        .replaceAll(RegExp(r'`(.+?)`'), r'$1')                 // inline code
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '') // bullets
        .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '') // numbered
        .replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'$1')       // links
        .replaceAll(RegExp(r'!\[.*?\]\(.+?\)'), '')            // images
        .replaceAll(RegExp(r'>\s?', multiLine: true), '')      // blockquotes
        .replaceAll(RegExp(r'\n{2,}'), '\n')                   // collapse blanks
        .trim();
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
