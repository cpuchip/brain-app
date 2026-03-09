import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/becoming_api.dart';

/// Entrypoint for the transparent WidgetFilterActivity.
/// Shows a category picker overlay, saves selection, updates widget, then closes.
@pragma('vm:entry-point')
void widgetFilterMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.brain_app/widget_filter');
  String filterType = 'practices';
  try {
    filterType =
        await channel.invokeMethod<String>('getFilterType') ?? 'practices';
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();
  final url = prefs.getString('brain_url') ?? 'https://ibeco.me';
  final token = prefs.getString('brain_token') ?? '';

  final api = BecomingApi(baseUrl: url, token: token);

  runApp(WidgetFilterApp(filterType: filterType, api: api));
}

class WidgetFilterApp extends StatelessWidget {
  final String filterType;
  final BecomingApi api;

  const WidgetFilterApp(
      {super.key, required this.filterType, required this.api});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: WidgetFilterScreen(filterType: filterType, api: api),
    );
  }
}

class WidgetFilterScreen extends StatefulWidget {
  final String filterType;
  final BecomingApi api;

  const WidgetFilterScreen(
      {super.key, required this.filterType, required this.api});

  @override
  State<WidgetFilterScreen> createState() => _WidgetFilterScreenState();
}

class _WidgetFilterScreenState extends State<WidgetFilterScreen> {
  List<String> _categories = [];
  String _current = 'All';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      // Read current filter
      final currentFilter =
          await HomeWidget.getWidgetData<String>('practice_filter') ?? 'All';

      // Fetch practices to get categories
      final practices = await widget.api.getPractices();
      final cats = <String>{};
      for (final p in practices) {
        if (p.category.isNotEmpty && p.type != 'memorize') {
          cats.add(p.category);
        }
      }
      final sorted = cats.toList()..sort();

      setState(() {
        _categories = ['All', ...sorted];
        _current = currentFilter;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load categories';
        _loading = false;
      });
    }
  }

  Future<void> _selectCategory(String category) async {
    await HomeWidget.saveWidgetData('practice_filter', category);
    await HomeWidget.updateWidget(name: 'PracticeWidgetProvider');
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => SystemNavigator.pop(),
      child: Scaffold(
        backgroundColor: Colors.black54,
        body: Center(
          child: GestureDetector(
            onTap: () {}, // absorb taps on the card
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Filter Practices',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const Divider(height: 1),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      )
                    else if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _categories.length,
                          itemBuilder: (context, i) {
                            final cat = _categories[i];
                            final isSelected = cat == _current;
                            return ListTile(
                              title: Text(cat),
                              leading: isSelected
                                  ? Icon(Icons.check,
                                      color:
                                          Theme.of(context).colorScheme.primary)
                                  : const SizedBox(width: 24),
                              onTap: () => _selectCategory(cat),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
