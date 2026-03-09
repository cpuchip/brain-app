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
        .take(4)
        .toList();

    await HomeWidget.saveWidgetData('action_count', actions.length);
    for (var i = 0; i < 4; i++) {
      if (i < actions.length) {
        await HomeWidget.saveWidgetData('entry_${i}_title', actions[i].title ?? '');
        await HomeWidget.saveWidgetData('entry_${i}_due', _relativeDue(actions[i]));
        await HomeWidget.saveWidgetData('entry_${i}_id', actions[i].id);
        await HomeWidget.saveWidgetData('entry_${i}_done', false);
      } else {
        await HomeWidget.saveWidgetData('entry_${i}_title', '');
        await HomeWidget.saveWidgetData('entry_${i}_due', '');
        await HomeWidget.saveWidgetData('entry_${i}_id', '');
        await HomeWidget.saveWidgetData('entry_${i}_done', false);
      }
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
  /// Filters by saved category preference.
  Future<void> updatePracticeWidget(List<DailySummary> summaries) async {
    // Read current filter
    final filter = await HomeWidget.getWidgetData<String>('practice_filter') ?? 'All';

    // Filter to non-memorize practices matching category
    var practices = summaries
        .where((s) => s.practiceType != 'memorize')
        .toList();
    if (filter != 'All') {
      practices = practices.where((s) => s.category == filter).toList();
    }

    // Save all practices (widget ListView is scrollable)
    final display = practices;

    await HomeWidget.saveWidgetData('practice_count', display.length);
    for (var i = 0; i < display.length; i++) {
      final p = display[i];
      await HomeWidget.saveWidgetData('practice_${i}_id', p.practiceId);
      await HomeWidget.saveWidgetData('practice_${i}_name', p.practiceName);
      await HomeWidget.saveWidgetData('practice_${i}_target_sets', p.targetSets);
      await HomeWidget.saveWidgetData('practice_${i}_completed_sets', p.completedSets);
    }

    await HomeWidget.updateWidget(name: _practiceWidgetName);
  }
}
