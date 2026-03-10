import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../services/becoming_api.dart';
import '../services/brain_api.dart';
import '../services/brain_service.dart';
import '../services/widget_service.dart';
import 'edit_entry_screen.dart';

class TodayScreen extends StatefulWidget {
  final BecomingApi becomingApi;
  final BrainApi brainApi;
  final Stream<EntryUpdatedEvent>? entryUpdated;

  const TodayScreen({
    super.key,
    required this.becomingApi,
    required this.brainApi,
    this.entryUpdated,
  });

  @override
  State<TodayScreen> createState() => TodayScreenState();
}

class TodayScreenState extends State<TodayScreen> {
  List<DailySummary>? _practices;
  List<Practice>? _dueCards;
  List<HistoryEntry>? _brainActions;
  bool _loading = true;
  String? _error;
  DateTime? _lastFetched;

  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  /// Public method so parent can trigger refresh (e.g. on tab focus).
  void refresh() => _loadAll();

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        widget.becomingApi.getDailySummary(_today),
        widget.becomingApi.getDueCards(_today),
        _loadBrainActions(),
      ]);

      if (!mounted) return;
      setState(() {
        _practices = results[0] as List<DailySummary>;
        _dueCards = results[1] as List<Practice>;
        _brainActions = results[2] as List<HistoryEntry>;
        _loading = false;
        _lastFetched = DateTime.now();
      });

      // Push practice data to widget
      WidgetService().updatePracticeWidget(_practices!).catchError((_) {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<List<HistoryEntry>> _loadBrainActions() async {
    try {
      final entries = await widget.brainApi.getHistory(limit: 50);
      final today = DateTime.now();
      return entries.where((e) {
        if (e.isDone) return false;
        if (e.dueDate == null || e.dueDate!.isEmpty) return false;
        final due = DateTime.tryParse(e.dueDate!);
        if (due == null) return false;
        return !due.isAfter(DateTime(today.year, today.month, today.day, 23, 59, 59));
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _logPracticeSet(DailySummary practice) async {
    // Optimistic update
    setState(() {
      final idx = _practices?.indexWhere((p) => p.practiceId == practice.practiceId);
      if (idx != null && idx >= 0) {
        final old = _practices![idx];
        _practices![idx] = DailySummary(
          practiceId: old.practiceId,
          practiceName: old.practiceName,
          practiceType: old.practiceType,
          category: old.category,
          config: old.config,
          status: old.status,
          endDate: old.endDate,
          startDate: old.startDate,
          createdAt: old.createdAt,
          logCount: old.logCount + 1,
          totalSets: (old.totalSets ?? 0) + 1,
          totalReps: old.totalReps,
          lastValue: old.lastValue,
          lastNotes: old.lastNotes,
          isDue: old.isDue,
          nextDue: old.nextDue,
          daysOverdue: old.daysOverdue,
          slotsDue: old.slotsDue,
        );
      }
    });

    try {
      await widget.becomingApi.logPractice(
        practiceId: practice.practiceId,
        date: _today,
        sets: 1,
        reps: practice.targetReps,
      );
    } catch (e) {
      // Revert on failure
      if (mounted) {
        _loadAll();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to log: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _undoPracticeSet(DailySummary practice) async {
    if (practice.completedSets <= 0) return;

    // Optimistic update
    setState(() {
      final idx = _practices?.indexWhere((p) => p.practiceId == practice.practiceId);
      if (idx != null && idx >= 0) {
        final old = _practices![idx];
        _practices![idx] = DailySummary(
          practiceId: old.practiceId,
          practiceName: old.practiceName,
          practiceType: old.practiceType,
          category: old.category,
          config: old.config,
          status: old.status,
          endDate: old.endDate,
          startDate: old.startDate,
          createdAt: old.createdAt,
          logCount: (old.logCount - 1).clamp(0, old.logCount),
          totalSets: ((old.totalSets ?? 1) - 1).clamp(0, old.totalSets ?? 1),
          totalReps: old.totalReps,
          lastValue: old.lastValue,
          lastNotes: old.lastNotes,
          isDue: old.isDue,
          nextDue: old.nextDue,
          daysOverdue: old.daysOverdue,
          slotsDue: old.slotsDue,
        );
      }
    });

    try {
      await widget.becomingApi.deleteLatestLog(
        practiceId: practice.practiceId,
        date: _today,
      );
    } catch (e) {
      if (mounted) {
        _loadAll();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to undo: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openBrainEntry(HistoryEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditEntryScreen(
          api: widget.brainApi,
          entry: entry,
          entryUpdated: widget.entryUpdated,
        ),
      ),
    );
  }

  void _showAddPractice() {
    // Collect categories from existing practices
    final cats = <String>{};
    for (final p in _practices ?? <DailySummary>[]) {
      for (final c in p.category.split(',')) {
        final trimmed = c.trim();
        if (trimmed.isNotEmpty) cats.add(trimmed);
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AddPracticeSheet(
        categories: cats.toList()..sort(),
        onSubmit: (name, type, category) async {
          await widget.becomingApi.createPractice(
            name: name,
            type: type,
            category: category,
          );
          if (mounted) _loadAll();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _practices == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _practices == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('Could not load today\'s data', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Header
          _buildHeader(context),
          const SizedBox(height: 16),

          // Memorize section
          if (_dueCards != null && _dueCards!.isNotEmpty) ...[
            _MemorizeSection(
              cards: _dueCards!,
              api: widget.becomingApi,
              today: _today,
              onReviewComplete: _loadAll,
            ),
            const SizedBox(height: 16),
          ],

          // Practices section
          if (_practices != null) ...[
            _PracticesSection(
              practices: _practices!,
              onLogSet: _logPracticeSet,
              onUndoSet: _undoPracticeSet,
              onAdd: _showAddPractice,
            ),
            const SizedBox(height: 16),
          ],

          // Brain actions section
          if (_brainActions != null && _brainActions!.isNotEmpty) ...[
            _BrainActionsSection(
              actions: _brainActions!,
              onTap: _openBrainEntry,
            ),
            const SizedBox(height: 16),
          ],

          // Last updated
          if (_lastFetched != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: Text(
                'Updated ${DateFormat.jm().format(_lastFetched!)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMMM d').format(now);

    final completed = _practices?.where((p) => p.isFullyComplete).length ?? 0;
    final total = _practices?.length ?? 0;
    final dueCards = _dueCards?.length ?? 0;
    final brainDue = _brainActions?.length ?? 0;
    final totalItems = total + dueCards + brainDue;
    final totalDone = completed; // memorize + brain track separately

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Today',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          dateStr,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        if (totalItems > 0) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: totalItems > 0 ? totalDone / totalItems : 0,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          Text(
            '$totalDone of $totalItems complete',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ],
    );
  }
}

// --- Memorize Section ---

class _MemorizeSection extends StatefulWidget {
  final List<Practice> cards;
  final BecomingApi api;
  final String today;
  final VoidCallback onReviewComplete;

  const _MemorizeSection({
    required this.cards,
    required this.api,
    required this.today,
    required this.onReviewComplete,
  });

  @override
  State<_MemorizeSection> createState() => _MemorizeSectionState();
}

class _MemorizeSectionState extends State<_MemorizeSection> {
  bool _expanded = true;
  int? _reviewingIndex;
  bool _revealed = false;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          // Section header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.auto_stories, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Scripture Memorize',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.cards.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),

          // Card list
          if (_expanded) ...[
            const Divider(height: 1),
            ...List.generate(widget.cards.length, (i) {
              final card = widget.cards[i];
              final isReviewing = _reviewingIndex == i;

              return Column(
                children: [
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  if (isReviewing)
                    _buildReviewFlow(card)
                  else
                    ListTile(
                      title: Text(card.name),
                      trailing: FilledButton.tonal(
                        onPressed: () => setState(() {
                          _reviewingIndex = i;
                          _revealed = false;
                        }),
                        child: const Text('Review'),
                      ),
                      dense: true,
                    ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewFlow(Practice card) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          if (!_revealed) ...[
            Text(
              'Try to recall from memory...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _revealed = true),
                icon: const Icon(Icons.visibility),
                label: const Text('Show answer'),
              ),
            ),
          ] else ...[
            // Show scripture body text
            if (card.description.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: MarkdownBody(
                  data: card.description,
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodyMedium,
                  ),
                ),
              )
            else
              Text(
                'No body text available.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                  fontStyle: FontStyle.italic,
                ),
              ),
            const SizedBox(height: 12),
            Center(
              child: FilledButton.icon(
                onPressed: _submitting ? null : () => _showRatingDialog(card),
                icon: const Icon(Icons.rate_review),
                label: const Text('Rate recall'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showRatingDialog(Practice card) async {
    final quality = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colorScheme = theme.colorScheme;
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'How well did you remember?',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _dialogQualityButton(ctx, 'Again', 1, Colors.red),
                    const SizedBox(width: 8),
                    _dialogQualityButton(ctx, 'Hard', 2, Colors.orange),
                    const SizedBox(width: 8),
                    _dialogQualityButton(ctx, 'Good', 4, Colors.green),
                    const SizedBox(width: 8),
                    _dialogQualityButton(ctx, 'Easy', 5, Colors.blue),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (quality != null) {
      _submitReview(quality);
    }
  }

  Widget _dialogQualityButton(BuildContext ctx, String label, int quality, Color color) {
    return Expanded(
      child: FilledButton.tonal(
        onPressed: () => Navigator.of(ctx).pop(quality),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: color)),
      ),
    );
  }

  Future<void> _submitReview(int quality) async {
    if (_reviewingIndex == null) return;
    final card = widget.cards[_reviewingIndex!];

    setState(() => _submitting = true);
    try {
      await widget.api.reviewCard(
        practiceId: card.id,
        quality: quality,
        date: widget.today,
      );
      if (!mounted) return;

      // Remove reviewed card and move on
      setState(() {
        widget.cards.removeAt(_reviewingIndex!);
        _reviewingIndex = null;
        _revealed = false;
        _submitting = false;
      });

      // If all done, refresh parent
      if (widget.cards.isEmpty) {
        widget.onReviewComplete();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Review failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// --- Practices Section ---

/// Whether a practice is due today (non-scheduled types are always due).
bool _isDueToday(DailySummary p) {
  if (p.practiceType == 'scheduled') return p.isDue == true;
  return true;
}

class _PracticesSection extends StatelessWidget {
  final List<DailySummary> practices;
  final ValueChanged<DailySummary> onLogSet;
  final ValueChanged<DailySummary> onUndoSet;
  final VoidCallback? onAdd;

  const _PracticesSection({
    required this.practices,
    required this.onLogSet,
    required this.onUndoSet,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Separate non-memorize practices (memorize has its own section)
    final nonMemorize = practices.where((p) => p.practiceType != 'memorize').toList();
    if (nonMemorize.isEmpty) return const SizedBox.shrink();

    // Sort: due+incomplete → due+complete → not-due
    nonMemorize.sort((a, b) {
      final aDue = _isDueToday(a);
      final bDue = _isDueToday(b);
      if (aDue != bDue) return aDue ? -1 : 1;
      if (aDue) {
        if (a.isFullyComplete != b.isFullyComplete) {
          return a.isFullyComplete ? 1 : -1;
        }
        return b.daysOverdue.compareTo(a.daysOverdue);
      }
      return 0;
    });

    // Progress: due items only
    final dueItems = nonMemorize.where(_isDueToday);
    final dueCompleted = dueItems.where((p) => p.isFullyComplete).length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Practices',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$dueCompleted/${dueItems.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
                const Spacer(),
                if (onAdd != null)
                  IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: onAdd,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Add practice',
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...nonMemorize.map((practice) => _PracticeTile(
                practice: practice,
                onLogSet: onLogSet,
                onUndoSet: onUndoSet,
              )),
        ],
      ),
    );
  }
}

class _PracticeTile extends StatelessWidget {
  final DailySummary practice;
  final ValueChanged<DailySummary> onLogSet;
  final ValueChanged<DailySummary> onUndoSet;

  const _PracticeTile({
    required this.practice,
    required this.onLogSet,
    required this.onUndoSet,
  });

  String? get _scheduleInfo {
    if (practice.practiceType == 'task') return 'one-time';
    if (practice.practiceType != 'scheduled') return null;
    try {
      final data = jsonDecode(practice.config) as Map<String, dynamic>;
      final schedType = data['schedule_type'] as String?;
      switch (schedType) {
        case 'interval':
          final days = data['interval_days'] ?? 1;
          return 'every ${days}d';
        case 'daily_slots':
          final slots = (data['daily_slots'] as List?)?.cast<String>() ?? [];
          return slots.join(', ');
        case 'weekly':
          final days = (data['weekly_days'] as List?)?.cast<String>() ?? [];
          return days.map((d) => d.length >= 3 ? d.substring(0, 3) : d).join(', ');
        case 'monthly':
          final day = data['monthly_day'] ?? 1;
          return 'monthly (day $day)';
        case 'once':
          return 'one-time';
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  String _relativeDue(String dateStr) {
    try {
      final due = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final diff = DateTime(due.year, due.month, due.day).difference(today).inDays;
      if (diff <= 0) return 'today';
      if (diff == 1) return 'tomorrow';
      return 'in ${diff}d';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final targetSets = practice.targetSets;
    final completedSets = practice.completedSets;
    final allDone = completedSets >= targetSets;
    final isDue = _isDueToday(practice);

    // Build subtitle spans
    final subtitleParts = <InlineSpan>[];
    if (practice.category.isNotEmpty) {
      subtitleParts.add(TextSpan(text: practice.category));
    }

    if (!isDue && practice.nextDue != null) {
      if (subtitleParts.isNotEmpty) subtitleParts.add(const TextSpan(text: ' · '));
      subtitleParts.add(TextSpan(text: 'next: ${_relativeDue(practice.nextDue!)}'));
    } else if (isDue && practice.daysOverdue > 0) {
      if (subtitleParts.isNotEmpty) subtitleParts.add(const TextSpan(text: ' · '));
      subtitleParts.add(TextSpan(
        text: '${practice.daysOverdue}d overdue',
        style: TextStyle(color: colorScheme.error),
      ));
    }

    final schedLabel = _scheduleInfo;
    if (schedLabel != null) {
      if (subtitleParts.isNotEmpty) subtitleParts.add(const TextSpan(text: ' · '));
      subtitleParts.add(TextSpan(text: schedLabel));
    }

    final tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  practice.practiceName,
                  style: allDone
                      ? TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: colorScheme.outline,
                        )
                      : null,
                ),
                if (subtitleParts.isNotEmpty)
                  Text.rich(
                    TextSpan(children: subtitleParts),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          // Set buttons (still actionable even when not due)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(targetSets, (i) {
              final setNum = i + 1;
              final isDone = setNum <= completedSets;
              return Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _SetButton(
                  setNum: setNum,
                  isDone: isDone,
                  onTap: () {
                    if (isDone) {
                      onUndoSet(practice);
                    } else {
                      onLogSet(practice);
                    }
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );

    // Dim not-due items but keep them interactive
    if (!isDue) {
      return Opacity(opacity: 0.5, child: tile);
    }
    return tile;
  }
}

class _SetButton extends StatelessWidget {
  final int setNum;
  final bool isDone;
  final VoidCallback onTap;

  const _SetButton({
    required this.setNum,
    required this.isDone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isDone ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: isDone
              ? Icon(Icons.check, size: 18, color: colorScheme.primary)
              : Text(
                  '$setNum',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.outline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}

// --- Add Practice Sheet ---

class _AddPracticeSheet extends StatefulWidget {
  final List<String> categories;
  final Future<void> Function(String name, String type, String category) onSubmit;

  const _AddPracticeSheet({
    required this.categories,
    required this.onSubmit,
  });

  @override
  State<_AddPracticeSheet> createState() => _AddPracticeSheetState();
}

class _AddPracticeSheetState extends State<_AddPracticeSheet> {
  final _nameController = TextEditingController();
  String _type = 'habit';
  String _category = '';
  bool _submitting = false;
  String? _error;

  static const _types = ['habit', 'tracker', 'scheduled', 'task'];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.onSubmit(name, _type, _category);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('New Practice', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),

          // Name
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),

          // Type chips
          Text('Type', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _types.map((t) => ChoiceChip(
                  label: Text(t),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                )).toList(),
          ),
          const SizedBox(height: 16),

          // Category chips (from existing practices)
          if (widget.categories.isNotEmpty) ...[
            Text('Category', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                // "None" option
                ChoiceChip(
                  label: const Text('none'),
                  selected: _category.isEmpty,
                  onSelected: (_) => setState(() => _category = ''),
                ),
                ...widget.categories.map((c) => ChoiceChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    )),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Error
          if (_error != null) ...[
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],

          // Submit
          FilledButton(
            onPressed: _submitting || _nameController.text.trim().isEmpty ? null : _submit,
            child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create'),
          ),
        ],
      ),
    );
  }
}

// --- Brain Actions Section ---

class _BrainActionsSection extends StatelessWidget {
  final List<HistoryEntry> actions;
  final ValueChanged<HistoryEntry> onTap;

  const _BrainActionsSection({
    required this.actions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.psychology, color: colorScheme.tertiary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Brain Actions',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${actions.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...actions.map((entry) => ListTile(
                title: Text(entry.title ?? entry.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: entry.dueDate != null
                    ? Text(
                        _dueDateLabel(entry.dueDate!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _isOverdue(entry.dueDate!) ? colorScheme.error : colorScheme.outline,
                        ),
                      )
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onTap(entry),
                dense: true,
              )),
        ],
      ),
    );
  }

  bool _isOverdue(String dateStr) {
    final due = DateTime.tryParse(dateStr);
    if (due == null) return false;
    final today = DateTime.now();
    return due.isBefore(DateTime(today.year, today.month, today.day));
  }

  String _dueDateLabel(String dateStr) {
    final due = DateTime.tryParse(dateStr);
    if (due == null) return dateStr;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final dueDate = DateTime(due.year, due.month, due.day);
    final diff = dueDate.difference(todayDate).inDays;
    if (diff < 0) return '${-diff} day${diff == -1 ? "" : "s"} overdue';
    if (diff == 0) return 'Due today';
    return 'Due in $diff day${diff == 1 ? "" : "s"}';
  }
}
