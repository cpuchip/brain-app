# Brain App — Near-Term Feature Spec

> Implementation guide for the next wave of brain-app features.
> Each feature is self-contained and can be built independently, though some share infrastructure.

---

## 1. Search & Filter Entries

**Goal:** Find entries fast — by text, category, or status — without scrolling through a flat list.

### Backend Support (already exists)

| Mode | Endpoint | Notes |
|------|----------|-------|
| Direct | `GET /api/search?q=X&limit=20` | Full-text on title + body |
| Direct | `GET /api/search/semantic?q=X&category=C&limit=10` | Vector similarity |
| Direct | `GET /api/entries?category=X&needs_review=true` | Filter by category or review flag |
| Relay | `GET /api/brain/entries?category=X` | Category filter only |

**Relay gap:** No search endpoint on the relay side today. Options:
- **Option A (recommended):** Add `GET /api/brain/entries/search?q=X` to ibeco.me that searches `brain_entries` with SQL LIKE or FTS.
- **Option B:** Client-side filter — fetch all entries, filter in Dart. Works for < 500 entries but doesn't scale.

### Flutter Implementation

**New in `brain_api.dart`:**

```dart
Future<List<HistoryEntry>> searchEntries(String query, {String? category}) async {
  if (hasBrainUrl) {
    // Direct: /api/search?q=query&limit=50
    final url = '$brainUrl/api/search?q=${Uri.encodeComponent(query)}&limit=50';
    // Parse response.entries
  } else {
    // Relay: /api/brain/entries/search?q=query  (new endpoint)
    // OR client-side filter as fallback
  }
}
```

**UI changes to `history_screen.dart`:**

1. **Search bar** — persistent `TextField` at the top of the screen with search icon, debounced 300ms
2. **Filter chips** — horizontal `SingleChildScrollView` of `FilterChip` widgets below the search bar:
   - Categories: All, Actions, Projects, Ideas, People, Study, Journal, Inbox
   - Status: Active, Done, Needs Review
3. **Results list** — replaces the current flat list, same card UI
4. **Empty state** — "No entries match your search" with clear-filters button

**State management:**
```dart
String _searchQuery = '';
String? _categoryFilter;
bool _showCompleted = false;
Timer? _debounce;

// On text change:
void _onSearchChanged(String query) {
  _debounce?.cancel();
  _debounce = Timer(Duration(milliseconds: 300), () {
    setState(() { _searchQuery = query; });
    _loadEntries();
  });
}
```

**Keyboard:** Search field auto-focuses when user taps a search icon in the AppBar. Dismiss keyboard on scroll.

### Acceptance Criteria

- [ ] Type in search bar → results filter in real time (debounced)
- [ ] Tap category chip → only that category shown
- [ ] "Active" chip hides done entries; toggling "Done" shows completed
- [ ] Clear search (X button) restores full list
- [ ] Works in both relay and direct mode
- [ ] Empty state shown when no matches

---

## 2. Create Entries Directly

**Goal:** Add a brain entry with full fields from the app — not just voice capture. Think: quick-add an action with a due date, or jot down an idea with tags.

### Backend Support (already exists)

| Mode | Endpoint | Body |
|------|----------|------|
| Direct | `POST /api/entries` | `{title, body, category?, tags?, source?}` → 201 + entry |
| Relay | `POST /api/brain/entries` | Same shape, relayed to agent |

### Flutter Implementation

**New screen: `create_entry_screen.dart`**

Reuses the same form layout as `EditEntryScreen` but starts empty. Key differences:
- Title: "New Entry" in AppBar
- Save calls `createEntry()` instead of `updateEntry()`
- Category defaults to "inbox" (user can change)
- Source set to `"app"`

**New in `brain_api.dart`:**
```dart
Future<HistoryEntry?> createEntry({
  required String title,
  required String body,
  String category = 'inbox',
  List<String>? tags,
  String? dueDate,
  String? nextAction,
  String? status,
}) async {
  final payload = {
    'title': title,
    'body': body,
    'category': category,
    'source': 'app',
    if (tags != null && tags.isNotEmpty) 'tags': tags,
    if (dueDate != null) 'due_date': dueDate,
    if (nextAction != null) 'next_action': nextAction,
    if (status != null) 'status': status,
  };

  if (hasBrainUrl) {
    // POST $brainUrl/api/entries
  } else {
    // POST $baseUrl/api/brain/entries
  }
}
```

**Entry points:**
1. **FAB on HistoryScreen** — FloatingActionButton with `Icons.add`, navigates to CreateEntryScreen
2. **Quick-add from HomeScreen** — Optional: long-press the send button to "create as entry" instead of classify

**Form validation:**
- Title required (min 1 char)
- Body required (min 1 char)
- Category from dropdown (defaults to inbox)

### Acceptance Criteria

- [ ] Tap FAB on history → create form opens
- [ ] Fill title + body + category → save → entry appears in history
- [ ] Due date, tags, next action, status all optional and work
- [ ] Works in both relay and direct mode
- [ ] Dirty tracking + discard confirmation (reuse from EditEntryScreen)

---

## 3. Offline Queue

**Goal:** Never lose a thought. If the phone has no connection, capture it locally and sync when back online.

### Architecture

```
User captures thought (voice or text)
  ↓
Check connectivity
  ├─ Online → send via WebSocket/REST as today
  └─ Offline → save to local SQLite queue
                  ↓
              ConnectivityMonitor detects network return
                  ↓
              Drain queue: send each pending thought
                  ↓
              On success → remove from queue
              On failure → retry with backoff
```

### New Dependencies

```yaml
# pubspec.yaml
sqflite: ^2.4.2           # Local SQLite for offline queue
connectivity_plus: ^6.1.4  # Network state monitoring
path_provider: ^2.1.5      # DB file location
```

### New Service: `offline_queue.dart`

```dart
class OfflineQueue {
  late Database _db;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase('${dir.path}/brain_queue.db', version: 1,
      onCreate: (db, v) => db.execute('''
        CREATE TABLE queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,       -- 'thought' | 'entry_create' | 'entry_update'
          payload TEXT NOT NULL,    -- JSON
          created_at TEXT NOT NULL,
          attempts INTEGER DEFAULT 0
        )
      '''));
  }

  Future<void> enqueue(String type, Map<String, dynamic> payload);
  Future<List<QueueItem>> pending();
  Future<void> dequeue(int id);
  Future<void> incrementAttempts(int id);
  Future<int> count();
}
```

### Connectivity Monitor

```dart
class ConnectivityMonitor {
  final _connectivity = Connectivity();
  final OfflineQueue _queue;
  final BrainService _brain;
  final BrainApi _api;

  void start() {
    _connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        _drainQueue();
      }
    });
  }

  Future<void> _drainQueue() async {
    final items = await _queue.pending();
    for (final item in items) {
      try {
        switch (item.type) {
          case 'thought':
            await _brain.sendThought(item.payload['text']);
          case 'entry_create':
            await _api.createEntry(...item.payload);
          case 'entry_update':
            await _api.updateEntry(item.payload['id'], item.payload['updates']);
        }
        await _queue.dequeue(item.id);
      } catch (e) {
        await _queue.incrementAttempts(item.id);
        if (item.attempts > 5) break; // stop retrying after 5 failures
      }
    }
  }
}
```

### UI Integration

- **HomeScreen:** When sending a thought while offline, show snackbar: "Saved offline — will sync when connected"
- **ConnectionIndicator:** Show queue count badge when items are pending (e.g., red dot with number)
- **HistoryScreen:** Pending queue items shown at top with "Pending sync" label

### Acceptance Criteria

- [ ] Toggle airplane mode → capture a voice thought → saves locally
- [ ] Turn off airplane mode → thought syncs automatically
- [ ] Queue count visible in connection indicator
- [ ] Pending items visible in history with "waiting to sync" badge
- [ ] Failed syncs retry up to 5 times with backoff
- [ ] No data loss on app restart (SQLite persists)

---

## 4. Notification Reminders

**Goal:** Don't forget due-date entries. Surface them as Android local notifications so brain entries find you instead of you finding them.

### New Dependencies

```yaml
flutter_local_notifications: ^19.0.0  # Local notification scheduling
timezone: ^0.10.0                      # Timezone-aware scheduling
permission_handler: ^11.4.0           # Request notification permission (Android 13+)
```

### Android Setup

**`AndroidManifest.xml` additions:**
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>

<receiver android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"
          android:exported="false">
  <intent-filter>
    <action android:name="android.intent.action.BOOT_COMPLETED"/>
  </intent-filter>
</receiver>
```

### New Service: `notification_service.dart`

```dart
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _onTap,
    );
  }

  Future<bool> requestPermission() async {
    // Android 13+ requires explicit notification permission
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Schedule a reminder for a due-date entry.
  /// Fires at 8:00 AM on the due date.
  Future<void> scheduleReminder(HistoryEntry entry) async {
    if (entry.dueDate == null) return;
    final dueDate = DateTime.parse(entry.dueDate!);
    final scheduledTime = TZDateTime(
      tz.local, dueDate.year, dueDate.month, dueDate.day, 8, 0,
    );
    if (scheduledTime.isBefore(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      entry.id.hashCode,  // unique notification ID
      entry.title ?? 'Brain Reminder',
      _buildBody(entry),
      scheduledTime,
      NotificationDetails(android: AndroidNotificationDetails(
        'brain_reminders', 'Reminders',
        channelDescription: 'Due date reminders for brain entries',
        importance: Importance.high,
        priority: Priority.high,
      )),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: entry.id,  // entry ID for tap handling
    );
  }

  /// Cancel a reminder (e.g., entry marked done or deleted).
  Future<void> cancelReminder(String entryId) async {
    await _plugin.cancel(entryId.hashCode);
  }

  /// Rebuild all reminders from current entry list.
  /// Call after sync, bulk update, or app start.
  Future<void> rebuildReminders(List<HistoryEntry> entries) async {
    await _plugin.cancelAll();
    for (final entry in entries) {
      if (entry.isActionable && !entry.isDone && entry.dueDate != null) {
        await scheduleReminder(entry);
      }
    }
  }

  String _buildBody(HistoryEntry entry) {
    final parts = <String>[];
    if (entry.nextAction != null) parts.add('Next: ${entry.nextAction}');
    parts.add(entry.category ?? 'inbox');
    return parts.join(' · ');
  }

  void _onTap(NotificationResponse response) {
    // Navigate to EditEntryScreen for the tapped entry
    // Implementation depends on navigation approach (see Quick Actions below)
  }
}
```

### Scheduling Triggers

Reminders are scheduled/cancelled at these points:
1. **App start** → `rebuildReminders()` with all actionable entries
2. **After sync** (history load, offline drain) → `rebuildReminders()`
3. **Entry saved** (edit screen) → `scheduleReminder()` or `cancelReminder()`
4. **Entry marked done** → `cancelReminder()`
5. **Entry deleted** → `cancelReminder()`

### Settings

Add to SettingsScreen:
- **Toggle:** "Due date reminders" (on/off, stored in SharedPreferences)
- **Time picker:** "Remind me at" (default 8:00 AM, stored in SharedPreferences)

### Acceptance Criteria

- [ ] Entry with due date tomorrow → notification fires at 8 AM tomorrow
- [ ] Edit due date → old notification cancelled, new one scheduled
- [ ] Mark entry done → notification cancelled
- [ ] Delete entry → notification cancelled
- [ ] Toggle off in settings → all notifications cancelled
- [ ] App restart → reminders rebuilt from entry data
- [ ] Android 13+ → permission requested on first enable

---

## 5. Quick Actions from Notifications

**Goal:** Act on brain entries without opening the full app. See a reminder, mark done or snooze — all from the notification shade.

### Dependencies

Same as Notification Reminders (flutter_local_notifications supports action buttons).

### Implementation

**Notification actions (Android):**

```dart
const _markDoneAction = AndroidNotificationAction(
  'mark_done', 'Done ✓',
  showsUserInterface: false,
);

const _snoozeAction = AndroidNotificationAction(
  'snooze', 'Snooze 1h',
  showsUserInterface: false,
);

const _openAction = AndroidNotificationAction(
  'open', 'Open',
  showsUserInterface: true,  // launches app
);
```

**Updated notification channel:**
```dart
AndroidNotificationDetails(
  'brain_reminders', 'Reminders',
  channelDescription: 'Due date reminders for brain entries',
  importance: Importance.high,
  priority: Priority.high,
  actions: [_markDoneAction, _snoozeAction, _openAction],
)
```

**Action handler:**
```dart
void _onTap(NotificationResponse response) {
  final entryId = response.payload;
  if (entryId == null) return;

  switch (response.actionId) {
    case 'mark_done':
      // Toggle done via API (fire-and-forget from background)
      _markEntryDone(entryId);
    case 'snooze':
      // Reschedule notification for 1 hour from now
      _snoozeReminder(entryId, Duration(hours: 1));
    case 'open':
    default:
      // Navigate to EditEntryScreen
      _navigateToEntry(entryId);
  }
}
```

**Background execution concern:** "Mark done" and "Snooze" run without launching the app UI. The `flutter_local_notifications` plugin supports background action handling, but the API call requires credentials. Solution:
- Store credentials in `SharedPreferences` (already done)
- Create a lightweight `BrainApi` instance in the background handler
- Fire the update, cancel the notification

### Navigation from Notification

When the user taps "Open" (or taps the notification body), the app needs to navigate to the right entry. Two approaches:

**Option A — Global navigator key (simpler):**
```dart
// In main.dart
final navigatorKey = GlobalKey<NavigatorState>();

// In MaterialApp
navigatorKey: navigatorKey,

// In notification handler
navigatorKey.currentState?.push(
  MaterialPageRoute(builder: (_) => EditEntryScreen(api: api, entry: entry)),
);
```

**Option B — Deep link URI (more robust, needed later for widget too):**
- Register a custom URI scheme: `brainapp://entry/{id}`
- Handle in `main.dart` with platform channel or uni_links package
- Same mechanism reused by widget taps

Recommend **Option A** for now, refactor to **Option B** when widget is implemented (they share the same navigation need).

### Acceptance Criteria

- [ ] Notification shows three action buttons: Done, Snooze, Open
- [ ] "Done" marks entry done without opening app
- [ ] "Snooze" reschedules notification for 1 hour later
- [ ] "Open" launches app directly to that entry's edit screen
- [ ] Tapping notification body (not a button) opens the entry
- [ ] Actions work even when app is in background/killed

---

## 6. Home Screen Widget

**Goal:** See today's actions at a glance and capture ideas by voice — without opening the app.

### New Dependency

```yaml
home_widget: ^0.7.0  # Android (and iOS) home screen widgets
```

### Android Widget Layout

**Size:** 4×2 cells (standard "medium" widget)

**Layout sketch:**
```
┌──────────────────────────────────────────┐
│  🧠 Brain              Today: 3 actions  │
│──────────────────────────────────────────│
│  ☐ Review PR for auth refactor     due   │
│  ☐ Email landlord about lease      today │
│  ☐ Prep Sunday School lesson       tmrw  │
│──────────────────────────────────────────│
│                                    🎤    │
└──────────────────────────────────────────┘
```

**Elements:**
1. **Header row** — App icon + "Brain" + action count badge
2. **Entry list** — Up to 3-4 due/active action entries (title + relative due date)
3. **Mic FAB** — Bottom-right, launches voice capture overlay

### Android Implementation

**`android/app/src/main/res/layout/brain_widget.xml`:**
```xml
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:background="@drawable/widget_background"
    android:padding="12dp">

    <!-- Header -->
    <LinearLayout android:orientation="horizontal" ...>
        <ImageView android:src="@mipmap/ic_launcher" ... />
        <TextView android:id="@+id/widget_title" android:text="Brain" ... />
        <TextView android:id="@+id/widget_count" ... />
    </LinearLayout>

    <!-- Entry list (up to 4 items) -->
    <TextView android:id="@+id/entry_1" android:visibility="gone" ... />
    <TextView android:id="@+id/entry_2" android:visibility="gone" ... />
    <TextView android:id="@+id/entry_3" android:visibility="gone" ... />
    <TextView android:id="@+id/entry_4" android:visibility="gone" ... />

    <!-- Empty state -->
    <TextView android:id="@+id/empty_state" android:text="No actions due" ... />

    <!-- Mic button -->
    <ImageButton android:id="@+id/mic_button"
        android:src="@drawable/ic_mic"
        android:layout_gravity="end"
        android:contentDescription="Voice capture" ... />
</LinearLayout>
```

**`android/app/src/main/java/.../BrainWidgetProvider.kt`:**
- Extends `HomeWidgetProvider` (from home_widget package)
- `onUpdate()`: reads cached entry data from SharedPreferences, populates TextViews
- Mic button click → launches app with `voice_capture` intent extra
- Entry tap → launches app to history screen

### Flutter Side (home_widget integration)

**New service: `widget_service.dart`:**

```dart
class WidgetService {
  static const _widgetName = 'BrainWidgetProvider';

  /// Update widget data after entry sync.
  Future<void> updateWidget(List<HistoryEntry> entries) async {
    final actions = entries
        .where((e) => e.isActionable && !e.isDone)
        .where((e) => _isDueSoon(e))
        .take(4)
        .toList();

    // Store data for native widget to read
    await HomeWidget.saveWidgetData('action_count', actions.length);
    for (var i = 0; i < 4; i++) {
      if (i < actions.length) {
        await HomeWidget.saveWidgetData('entry_${i}_title', actions[i].title ?? '');
        await HomeWidget.saveWidgetData('entry_${i}_due', _relativeDue(actions[i]));
        await HomeWidget.saveWidgetData('entry_${i}_id', actions[i].id);
      } else {
        await HomeWidget.saveWidgetData('entry_${i}_title', '');
      }
    }

    // Tell Android to redraw
    await HomeWidget.updateWidget(name: _widgetName);
  }

  bool _isDueSoon(HistoryEntry e) {
    if (e.dueDate == null) return e.isActionable;
    final due = DateTime.parse(e.dueDate!);
    return due.difference(DateTime.now()).inDays <= 1; // today or tomorrow
  }

  String _relativeDue(HistoryEntry e) {
    if (e.dueDate == null) return '';
    final due = DateTime.parse(e.dueDate!);
    final diff = due.difference(DateTime.now().copyWith(hour: 0, minute: 0));
    if (diff.inDays <= 0) return 'today';
    if (diff.inDays == 1) return 'tmrw';
    return DateFormat('MMM d').format(due);
  }
}
```

**Widget update triggers:**
1. After history load / refresh
2. After offline queue drain
3. After entry edit/create/delete
4. Periodic (every 30 min via `HomeWidget.registerBackgroundCallback`)

### Voice Capture from Widget

**Flow:**
```
User taps mic icon on widget
  ↓
Android launches Flutter app with intent extra: voice_capture=true
  ↓
main.dart detects intent → navigates to HomeScreen with autoListen=true
  ↓
HomeScreen.initState checks autoListen → starts speech recognition immediately
  ↓
User speaks → thought captured → classified → widget updated
```

**Intent handling in `main.dart`:**
```dart
// In AppShell.initState or a one-time check
HomeWidget.widgetClicked.listen((uri) {
  if (uri?.host == 'voice_capture') {
    // Navigate to HomeScreen with autoListen flag
    _navigateToHome(autoListen: true);
  } else if (uri?.host == 'open_entry') {
    final entryId = uri?.pathSegments.first;
    _navigateToEntry(entryId);
  }
});
```

**Quick return:** After voice capture completes and the thought is sent, minimize the app (return to home screen) so the interaction feels lightweight — tap mic, speak, done.

### Android Manifest

```xml
<receiver android:name="com.stuffleberry.brain_app.BrainWidgetProvider"
    android:exported="true">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
    </intent-filter>
    <meta-data android:name="android.appwidget.provider"
        android:resource="@xml/brain_widget_info"/>
</receiver>
```

### Acceptance Criteria

- [ ] Widget appears in Android widget picker as "Brain"
- [ ] Shows up to 4 due/active actions with relative dates
- [ ] Empty state shows "No actions due" when nothing is upcoming
- [ ] Tap an entry → app opens to that entry
- [ ] Tap mic → app opens and immediately starts listening
- [ ] After voice capture → thought sent → app minimizes back to home
- [ ] Widget data refreshes after sync, edit, create, delete
- [ ] Widget updates periodically even when app isn't running

---

## Implementation Order

Recommended build sequence, based on dependencies and user value:

```
Phase 1 — Search & Create (independent, high daily-use value)
  ├── 1. Search/filter entries
  └── 2. Create entries directly

Phase 2 — Notifications (builds on existing data, no new infra)
  ├── 3. Notification reminders
  └── 4. Quick actions from notifications

Phase 3 — Widget (uses notification + voice infra)
  └── 5. Home screen widget

Phase 4 — Offline (most complex, least urgent if connectivity is good)
  └── 6. Offline queue
```

**Rationale:**
- Search + Create are the most-used missing features and have zero dependencies.
- Notifications use the existing entry data and scheduling is straightforward.
- Widget reuses the notification navigation pattern + existing voice capture.
- Offline queue is the most infrastructure-heavy and can wait until the app is used in low-connectivity situations.

---

## Shared Infrastructure

These pieces are used by multiple features — build them once:

1. **Global navigator key** — needed by notification taps + widget taps. Add to `main.dart`.
2. **Entry refresh callback** — after any mutation (create, edit, delete, sync), refresh history + rebuild notifications + update widget. Create a single `refreshAll()` in a shared place.
3. **Credential access from background** — notifications and widget updates need API credentials without the full app running. `SharedPreferences` is already used for this.
