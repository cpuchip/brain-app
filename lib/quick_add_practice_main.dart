import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/becoming_api.dart';
import 'services/widget_service.dart';

/// Entrypoint for the transparent QuickAddPracticeActivity.
/// Shows a quick-add overlay, creates the practice, refreshes widgets, then closes.
@pragma('vm:entry-point')
void quickAddPracticeMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final url = prefs.getString('brain_url') ?? 'https://ibeco.me';
  final token = prefs.getString('brain_token') ?? '';

  final api = BecomingApi(baseUrl: url, token: token);

  runApp(QuickAddPracticeApp(api: api));
}

class QuickAddPracticeApp extends StatelessWidget {
  final BecomingApi api;

  const QuickAddPracticeApp({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: _QuickAddPracticeScreen(api: api),
    );
  }
}

class _QuickAddPracticeScreen extends StatefulWidget {
  final BecomingApi api;

  const _QuickAddPracticeScreen({required this.api});

  @override
  State<_QuickAddPracticeScreen> createState() =>
      _QuickAddPracticeScreenState();
}

class _QuickAddPracticeScreenState extends State<_QuickAddPracticeScreen> {
  final _nameController = TextEditingController();
  String _type = 'habit';
  String _category = '';
  List<String> _categories = [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  static const _types = ['habit', 'tracker', 'scheduled', 'task'];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final practices = await widget.api.getPractices();
      final cats = <String>{};
      for (final p in practices) {
        for (final c in p.category.split(',')) {
          final trimmed = c.trim();
          if (trimmed.isNotEmpty) cats.add(trimmed);
        }
      }
      if (mounted) {
        setState(() {
          _categories = cats.toList()..sort();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load categories';
        });
      }
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.api.createPractice(
        name: name,
        type: _type,
        category: _category,
      );

      // Refresh widget data
      try {
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final practices = await widget.api.getDailySummary(today);
        await WidgetService().updatePracticeWidget(practices);
      } catch (_) {}

      if (mounted) {
        // Close the transparent overlay
        SystemNavigator.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
      }
    }
  }

  void _close() {
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.black54,
      body: GestureDetector(
        onTap: _close,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // prevent pass-through
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'New Practice',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

                        // Type
                        Text('Type', style: theme.textTheme.labelMedium),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: _types
                              .map((t) => ChoiceChip(
                                    label: Text(t),
                                    selected: _type == t,
                                    onSelected: (_) =>
                                        setState(() => _type = t),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 16),

                        // Category
                        if (_categories.isNotEmpty) ...[
                          Text('Category',
                              style: theme.textTheme.labelMedium),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('none'),
                                selected: _category.isEmpty,
                                onSelected: (_) =>
                                    setState(() => _category = ''),
                              ),
                              ..._categories.map((c) => ChoiceChip(
                                    label: Text(c),
                                    selected: _category == c,
                                    onSelected: (_) =>
                                        setState(() => _category = c),
                                  )),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Error
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: colorScheme.error),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _close,
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _submitting ||
                                      _nameController.text.trim().isEmpty
                                  ? null
                                  : _submit,
                              child: _submitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('Create'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
