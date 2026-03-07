import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Try loading .env (bundled asset), silently ignore if missing
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  runApp(const BrainApp());
}

class BrainApp extends StatelessWidget {
  const BrainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brain',
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
