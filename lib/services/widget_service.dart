import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'brain_api.dart';
import 'becoming_api.dart';

/// Manages home screen widget data updates.
class WidgetService {
  static const _widgetName = 'BrainWidgetProvider';
  static const _practiceWidgetName = 'PracticeWidgetProvider';

  /// Update widget data with current actionable entries.
  Future<void> updateWidget(List<HistoryEntry> entries) async {
    final actions = entries
        .where((e) => e.isActionable && !e.isDone)
        .where((e) => _isDueSoon(e))
        .toList();

    await HomeWidget.saveWidgetData('action_count', actions.length);
    for (var i = 0; i < actions.length; i++) {
      await HomeWidget.saveWidgetData('entry_${i}_title', actions[i].title ?? '');
      await HomeWidget.saveWidgetData('entry_${i}_due', _relativeDue(actions[i]));
      await HomeWidget.saveWidgetData('entry_${i}_id', actions[i].id);
      await HomeWidget.saveWidgetData('entry_${i}_done', false);
    }

    await HomeWidget.updateWidget(name: _widgetName);
  }

  bool _isDueSoon(HistoryEntry e) {
    if (e.dueDate == null || e.dueDate!.isEmpty) return e.isActionable;
    final due = DateTime.tryParse(e.dueDate!);
    if (due == null) return true;
    return due.difference(DateTime.now()).inDays <= 1;
  }

  String _relativeDue(HistoryEntry e) {
    if (e.dueDate == null || e.dueDate!.isEmpty) return '';
    final due = DateTime.tryParse(e.dueDate!);
    if (due == null) return '';
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final diff = due.difference(todayStart).inDays;
    if (diff <= 0) return 'today';
    if (diff == 1) return 'tmrw';
    return DateFormat('MMM d').format(due);
  }

  /// Update practice widget with daily summary data.
  /// Pushes ALL non-memorize practices unfiltered — each widget instance
  /// filters locally by its per-instance category preference.
  Future<void> updatePracticeWidget(List<DailySummary> summaries) async {
    // Push all non-memorize practices (filtering happens per-widget in Kotlin)
    final practices = summaries
        .where((s) => s.practiceType != 'memorize')
        .toList();

    await HomeWidget.saveWidgetData('all_practice_count', practices.length);
    for (var i = 0; i < practices.length; i++) {
      final p = practices[i];
      await HomeWidget.saveWidgetData('all_practice_${i}_id', p.practiceId);
      await HomeWidget.saveWidgetData('all_practice_${i}_name', p.practiceName);
      await HomeWidget.saveWidgetData('all_practice_${i}_category', p.category);
      await HomeWidget.saveWidgetData('all_practice_${i}_target_sets', p.targetSets);
      await HomeWidget.saveWidgetData('all_practice_${i}_completed_sets', p.completedSets);
    }

    // Save available categories for the cycle-filter
    final cats = <String>{'All'};
    for (final p in practices) {
      if (p.category.isNotEmpty) cats.add(p.category);
    }
    final sorted = ['All', ...(cats.toList()..remove('All'))..sort()];
    await HomeWidget.saveWidgetData('practice_categories', sorted.join(','));

    await HomeWidget.updateWidget(name: _practiceWidgetName);
  }
}
