import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/quick_add_screen.dart';
import 'services/becoming_api.dart';
import 'services/notification_service.dart';
import 'services/offline_queue.dart';
import 'services/brain_api.dart';
import 'services/widget_service.dart';

/// Global navigator key for notification tap navigation.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register widget background callback for no-flash checkbox toggling
  HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);

  // Try loading .env (bundled asset), silently ignore if missing
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  // Initialize notification service early
  await NotificationService().init();

  // Initialize offline queue
  await OfflineQueue().init();

  runApp(const BrainApp());
}

class BrainApp extends StatelessWidget {
  const BrainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brain',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const AppShell(),
    );
  }
}

/// Background callback for widget interactivity (mark-done, etc.).
/// Runs in a background isolate — no UI, no app flash.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri == null) return;

  if (uri.host == 'done' && uri.pathSegments.isNotEmpty) {
    final entryId = uri.pathSegments.first;

    // Optimistic: mark done in widget prefs immediately
    for (var i = 0; i < 4; i++) {
      final slotId = await HomeWidget.getWidgetData<String>('entry_${i}_id');
      if (slotId == entryId) {
        await HomeWidget.saveWidgetData('entry_${i}_done', true);
        break;
      }
    }
    await HomeWidget.updateWidget(name: 'BrainWidgetProvider');

    // Call the API to persist the change
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('brain_url') ?? 'https://ibeco.me';
    final token = prefs.getString('brain_token') ?? '';
    final brainUrl = prefs.getString('brain_direct_url') ?? '';

    try {
      final api = BrainApi(baseUrl: url, token: token, brainUrl: brainUrl);
      await api.updateEntry(entryId, {'action_done': true});
    } catch (_) {
      // API failure — visual already updated, will resync on next refresh
    }
  }

  if (uri.host == 'practice-log' && uri.pathSegments.isNotEmpty) {
    final practiceId = int.tryParse(uri.pathSegments.first);
    if (practiceId == null) return;

    // Optimistic: bump completed_sets in widget prefs
    final count = await HomeWidget.getWidgetData<int>('practice_count') ?? 0;
    for (var i = 0; i < count; i++) {
      final id = await HomeWidget.getWidgetData<int>('practice_${i}_id');
      if (id == practiceId) {
        final completed = await HomeWidget.getWidgetData<int>('practice_${i}_completed_sets') ?? 0;
        await HomeWidget.saveWidgetData('practice_${i}_completed_sets', completed + 1);
        break;
      }
    }
    await HomeWidget.updateWidget(name: 'PracticeWidgetProvider');

    // Call the API
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('brain_url') ?? 'https://ibeco.me';
    final token = prefs.getString('brain_token') ?? '';
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      final api = BecomingApi(baseUrl: url, token: token);
      await api.logPractice(practiceId: practiceId, date: today, sets: 1);
    } catch (_) {}
  }

  if (uri.host == 'practice-undo' && uri.pathSegments.isNotEmpty) {
    final practiceId = int.tryParse(uri.pathSegments.first);
    if (practiceId == null) return;

    // Optimistic: decrement completed_sets in widget prefs
    final count = await HomeWidget.getWidgetData<int>('practice_count') ?? 0;
    for (var i = 0; i < count; i++) {
      final id = await HomeWidget.getWidgetData<int>('practice_${i}_id');
      if (id == practiceId) {
        final completed = await HomeWidget.getWidgetData<int>('practice_${i}_completed_sets') ?? 0;
        if (completed > 0) {
          await HomeWidget.saveWidgetData('practice_${i}_completed_sets', completed - 1);
        }
        break;
      }
    }
    await HomeWidget.updateWidget(name: 'PracticeWidgetProvider');

    // Call the API
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('brain_url') ?? 'https://ibeco.me';
    final token = prefs.getString('brain_token') ?? '';
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      final api = BecomingApi(baseUrl: url, token: token);
      await api.deleteLatestLog(practiceId: practiceId, date: today);
    } catch (_) {}
  }

  if (uri.host == 'refresh') {
    // Fetch fresh data from API and update all widgets
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('brain_url') ?? 'https://ibeco.me';
    final token = prefs.getString('brain_token') ?? '';
    final brainUrl = prefs.getString('brain_direct_url') ?? '';

    try {
      final api = BrainApi(baseUrl: url, token: token, brainUrl: brainUrl);
      final entries = await api.getHistory(limit: 50);
      await WidgetService().updateWidget(entries);
    } catch (_) {}

    try {
      final api = BecomingApi(baseUrl: url, token: token);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final practices = await api.getDailySummary(today);
      await WidgetService().updatePracticeWidget(practices);
    } catch (_) {}
  }

  if (uri.host == 'practice-cycle-filter') {
    // Cycle through available categories for the practice widget
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('brain_url') ?? 'https://ibeco.me';
    final token = prefs.getString('brain_token') ?? '';

    try {
      final api = BecomingApi(baseUrl: url, token: token);
      final practices = await api.getPractices();

      // Build category list: "All" + unique non-memorize categories
      final cats = <String>{'All'};
      for (final p in practices) {
        if (p.category.isNotEmpty && p.type != 'memorize') {
          cats.add(p.category);
        }
      }
      final sorted = ['All', ...(cats.toList()..remove('All'))..sort()];

      // Get current filter, advance to next
      final current = await HomeWidget.getWidgetData<String>('practice_filter') ?? 'All';
      final idx = sorted.indexOf(current);
      final next = sorted[(idx + 1) % sorted.length];

      await HomeWidget.saveWidgetData('practice_filter', next);

      // Refresh practice widget data with new filter
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final daily = await api.getDailySummary(today);
      await WidgetService().updatePracticeWidget(daily);
    } catch (_) {}
  }
}

/// Second entrypoint for the transparent QuickAddActivity.
/// Runs in a separate Flutter engine — loads its own credentials.
@pragma('vm:entry-point')
void quickAddMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read mode from the platform (defaults to 'text')
  const channel = MethodChannel('com.example.brain_app/quick_add');
  String mode = 'text';
  try {
    mode = await channel.invokeMethod<String>('getMode') ?? 'text';
  } catch (_) {}

  // Load credentials from SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final url = prefs.getString('brain_url') ?? 'https://ibeco.me';
  final token = prefs.getString('brain_token') ?? '';
  final brainUrl = prefs.getString('brain_direct_url') ?? '';

  final api = BrainApi(baseUrl: url, token: token, brainUrl: brainUrl);

  runApp(QuickAddApp(mode: mode, api: api));
}

class QuickAddApp extends StatelessWidget {
  final String mode;
  final BrainApi api;

  const QuickAddApp({super.key, required this.mode, required this.api});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: QuickAddScreen(mode: mode, api: api),
    );
  }
}

/// Root shell — checks for saved credentials, shows setup or home.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _loading = true;
  String? _url;
  String? _token;
  String _brainUrl = '';

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    // dotenv.env throws NotInitializedError if .env failed to load (e.g. web)
    String? envUrl;
    try {
      envUrl = dotenv.env['IBECOME_URL'];
    } catch (_) {}
    setState(() {
      _url = prefs.getString('brain_url') ?? envUrl ?? 'https://ibeco.me';
      _token = prefs.getString('brain_token') ?? '';
      _brainUrl = prefs.getString('brain_direct_url') ?? '';
      _loading = false;
    });
  }

  Future<void> _onSettingsSaved(String url, String token, String brainUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('brain_url', url);
    await prefs.setString('brain_token', token);
    await prefs.setString('brain_direct_url', brainUrl);
    setState(() {
      _url = url;
      _token = token;
      _brainUrl = brainUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_url == null || _url!.isEmpty || _token == null || _token!.isEmpty) {
      return SettingsScreen(
        initialUrl: _url ?? '',
        initialToken: _token ?? '',
        initialBrainUrl: _brainUrl,
        onSaved: _onSettingsSaved,
        firstRun: true,
      );
    }

    return HomeScreen(
      url: _url!,
      token: _token!,
      brainUrl: _brainUrl,
      onSettingsChanged: _onSettingsSaved,
    );
  }
}
