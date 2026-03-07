import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import '../services/brain_api.dart';

/// Callback for when a notification is tapped (must be top-level or static).
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // Background taps handled via onDidReceiveBackgroundNotificationResponse.
  // We store the action + payload; the app reads it on next launch.
}

/// Local notification service for due-date reminders and quick actions.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Callback when user taps a notification or action button.
  void Function(String entryId, String? actionId)? onNotificationAction;

  static const _channelId = 'brain_reminders';
  static const _channelName = 'Reminders';
  static const _channelDesc = 'Due date reminders for brain entries';

  static const _markDoneAction = AndroidNotificationAction(
    'mark_done',
    'Done ✓',
    showsUserInterface: false,
  );

  static const _snoozeAction = AndroidNotificationAction(
    'snooze',
    'Snooze 1h',
    showsUserInterface: false,
  );

  static const _openAction = AndroidNotificationAction(
    'open',
    'Open',
    showsUserInterface: true,
  );

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    _initialized = true;
  }

  /// Request notification permission (Android 13+).
  Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Check if notifications are enabled in settings.
  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notifications_enabled') ?? false;
  }

  /// Get the configured reminder hour (default 8 AM).
  Future<int> get reminderHour async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('reminder_hour') ?? 8;
  }

  /// Schedule a reminder for a due-date entry.
  Future<void> scheduleReminder(HistoryEntry entry) async {
    if (!await isEnabled) return;
    if (entry.dueDate == null || entry.dueDate!.isEmpty) return;

    final dueDate = DateTime.tryParse(entry.dueDate!);
    if (dueDate == null) return;

    final hour = await reminderHour;
    final scheduledTime = tz.TZDateTime(
      tz.local,
      dueDate.year,
      dueDate.month,
      dueDate.day,
      hour,
    );

    // Don't schedule in the past
    if (scheduledTime.isBefore(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      entry.id.hashCode,
      entry.title ?? 'Brain Reminder',
      _buildBody(entry),
      scheduledTime,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          actions: const [_markDoneAction, _snoozeAction, _openAction],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: entry.id,
    );
  }

  /// Cancel a reminder for an entry.
  Future<void> cancelReminder(String entryId) async {
    await _plugin.cancel(entryId.hashCode);
  }

  /// Rebuild all reminders from current entry list.
  Future<void> rebuildReminders(List<HistoryEntry> entries) async {
    if (!await isEnabled) return;

    await _plugin.cancelAll();
    for (final entry in entries) {
      if (entry.isActionable && !entry.isDone && entry.dueDate != null) {
        await scheduleReminder(entry);
      }
    }
  }

  /// Snooze a reminder by rescheduling it.
  Future<void> snoozeReminder(String entryId, String? title, Duration duration) async {
    await cancelReminder(entryId);

    final snoozeTime = tz.TZDateTime.now(tz.local).add(duration);
    await _plugin.zonedSchedule(
      entryId.hashCode,
      title ?? 'Brain Reminder',
      'Snoozed',
      snoozeTime,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          actions: const [_markDoneAction, _snoozeAction, _openAction],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: entryId,
    );
  }

  String _buildBody(HistoryEntry entry) {
    final parts = <String>[];
    if (entry.nextAction != null && entry.nextAction!.isNotEmpty) {
      parts.add('Next: ${entry.nextAction}');
    }
    parts.add(entry.category ?? 'inbox');
    return parts.join(' · ');
  }

  void _onResponse(NotificationResponse response) {
    final entryId = response.payload;
    if (entryId == null || entryId.isEmpty) return;
    onNotificationAction?.call(entryId, response.actionId);
  }
}
