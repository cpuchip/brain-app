import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'services/becoming_api.dart';
import 'services/widget_service.dart';
import 'widgets/practice_form.dart';

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
  List<String> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
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
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _onSubmit(PracticeFormData data) async {
    await widget.api.createPractice(
      name: data.name,
      type: data.type,
      category: data.category,
      description: data.description,
      config: data.config,
      startDate: data.startDate,
      endDate: data.endDate,
    );

    // Refresh widget data
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final practices = await widget.api.getDailySummary(today);
      await WidgetService().updatePracticeWidget(practices);
    } catch (_) {}

    if (mounted) SystemNavigator.pop();
  }

  void _close() {
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final navPadding = MediaQuery.of(context).viewPadding.bottom;

    return GestureDetector(
      onTap: _close,
      child: Scaffold(
        backgroundColor: Colors.black54,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned(
              left: 16,
              right: 16,
              top: 60,
              bottom: bottomInset + navPadding + 16,
              child: GestureDetector(
                onTap: () {}, // absorb taps so scrim doesn't dismiss
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 600),
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
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                              child: Text(
                                'New Practice',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Flexible(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                child: PracticeForm(
                                  existingCategories: _categories,
                                  onSubmit: _onSubmit,
                                  onCancel: _close,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
