import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/becoming_api.dart';
import '../services/brain_api.dart';
import '../services/brain_service.dart';
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

  Future<void> _completePractice(DailySummary practice) async {
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
          totalSets: old.totalSets,
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
      await widget.becomingApi.completePractice(practice.practiceId);
    } catch (e) {
      // Revert on failure
      if (mounted) {
        _loadAll();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete: $e'),
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
              onComplete: _completePractice,
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

    final completed = _practices?.where((p) => p.isCompletedToday).length ?? 0;
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
          Text(
            'Try to recall from memory...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),

          if (!_revealed)
            Center(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _revealed = true),
                icon: const Icon(Icons.visibility),
                label: const Text('Show answer'),
              ),
            )
          else ...[
            // Quality rating buttons
            Text(
              'How well did you remember?',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _qualityButton('Again', 1, Colors.red),
                const SizedBox(width: 8),
                _qualityButton('Hard', 2, Colors.orange),
                const SizedBox(width: 8),
                _qualityButton('Good', 4, Colors.green),
                const SizedBox(width: 8),
                _qualityButton('Easy', 5, Colors.blue),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _qualityButton(String label, int quality, Color color) {
    return Expanded(
      child: FilledButton.tonal(
        onPressed: _submitting ? null : () => _submitReview(quality),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        child: _submitting
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label, style: TextStyle(fontSize: 12, color: color)),
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

class _PracticesSection extends StatelessWidget {
  final List<DailySummary> practices;
  final ValueChanged<DailySummary> onComplete;

  const _PracticesSection({
    required this.practices,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final completed = practices.where((p) => p.isCompletedToday).length;

    // Separate non-memorize practices (memorize has its own section)
    final nonMemorize = practices.where((p) => p.practiceType != 'memorize').toList();
    if (nonMemorize.isEmpty) return const SizedBox.shrink();

    final nonMemCompleted = nonMemorize.where((p) => p.isCompletedToday).length;

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
                  '$nonMemCompleted/${nonMemorize.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...nonMemorize.map((practice) {
            final done = practice.isCompletedToday;
            return ListTile(
              leading: done
                  ? Icon(Icons.check_circle, color: colorScheme.primary)
                  : Icon(Icons.radio_button_unchecked, color: colorScheme.outline),
              title: Text(
                practice.practiceName,
                style: done
                    ? TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: colorScheme.outline,
                      )
                    : null,
              ),
              subtitle: practice.category.isNotEmpty
                  ? Text(practice.category, style: theme.textTheme.bodySmall)
                  : null,
              onTap: done ? null : () => onComplete(practice),
              dense: true,
            );
          }),
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
