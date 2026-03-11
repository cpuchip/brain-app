import 'dart:convert';
import 'package:flutter/material.dart';

/// Full-featured practice creation form matching ibeco.me.
/// Used by both the Today screen bottom sheet and the widget overlay.
class PracticeForm extends StatefulWidget {
  final List<String> existingCategories;
  final Future<void> Function(PracticeFormData data) onSubmit;
  final VoidCallback? onCancel;

  const PracticeForm({
    super.key,
    required this.existingCategories,
    required this.onSubmit,
    this.onCancel,
  });

  @override
  State<PracticeForm> createState() => _PracticeFormState();
}

class PracticeFormData {
  final String name;
  final String type;
  final String category;
  final String description;
  final String config;
  final String? startDate;
  final String? endDate;

  PracticeFormData({
    required this.name,
    required this.type,
    required this.category,
    required this.description,
    required this.config,
    this.startDate,
    this.endDate,
  });
}

class _PracticeFormState extends State<PracticeForm> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _type = 'habit';
  final Set<String> _selectedCategories = {};
  String _customCategory = '';
  bool _submitting = false;
  String? _error;

  // Tracker config
  int _targetSets = 2;
  int _targetReps = 15;
  String _unit = 'reps';

  // Memorize config
  int _dailyReps = 1;

  // Scheduled config
  String _scheduleType = 'interval';
  int _intervalDays = 2;
  bool _shiftOnEarly = true;
  final Set<String> _weeklyDays = {};
  int _monthlyDay = 1;
  String? _onceDueDate;
  final List<String> _dailySlots = ['morning', 'night'];
  final _slotController = TextEditingController();

  // Dates
  String? _startDate;
  String? _endDate;

  static const _types = ['habit', 'tracker', 'memorize', 'scheduled', 'task'];
  static const _units = ['reps', 'bottles', 'glasses', 'seconds', 'minutes'];
  static const _presetCategories = ['spiritual', 'scripture', 'pt', 'fitness', 'study', 'health'];
  static const _weekDays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _slotController.dispose();
    super.dispose();
  }

  String _buildConfig() {
    switch (_type) {
      case 'tracker':
        return jsonEncode({
          'target_sets': _targetSets,
          'target_reps': _targetReps,
          'unit': _unit,
        });
      case 'memorize':
        return jsonEncode({'target_daily_reps': _dailyReps});
      case 'scheduled':
        final sched = <String, dynamic>{'type': _scheduleType};
        switch (_scheduleType) {
          case 'interval':
            sched['interval_days'] = _intervalDays;
            sched['shift_on_early'] = _shiftOnEarly;
          case 'daily_slots':
            sched['slots'] = _dailySlots;
          case 'weekly':
            sched['days'] = _weeklyDays.toList();
          case 'monthly':
            sched['day_of_month'] = _monthlyDay;
          case 'once':
            if (_onceDueDate != null) sched['due_date'] = _onceDueDate;
        }
        return jsonEncode({'schedule': sched});
      default:
        return '{}';
    }
  }

  String _buildCategory() {
    final cats = <String>{..._selectedCategories};
    if (_customCategory.isNotEmpty) {
      for (final c in _customCategory.split(',')) {
        final trimmed = c.trim();
        if (trimmed.isNotEmpty) cats.add(trimmed);
      }
    }
    return cats.join(',');
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    // Validate scheduled requires at least one config choice
    if (_type == 'scheduled') {
      if (_scheduleType == 'weekly' && _weeklyDays.isEmpty) {
        setState(() => _error = 'Select at least one day');
        return;
      }
      if (_scheduleType == 'once' && _onceDueDate == null) {
        setState(() => _error = 'Pick a due date');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.onSubmit(PracticeFormData(
        name: name,
        type: _type,
        category: _buildCategory(),
        description: _descController.text.trim(),
        config: _buildConfig(),
        startDate: _startDate,
        endDate: _endDate,
      ));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
      }
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) {
      final formatted =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        if (isStart) {
          _startDate = formatted;
        } else {
          _endDate = formatted;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Name ---
        TextField(
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Name',
            hintText: _type == 'memorize' ? 'D&C 93:29' : 'Practice name',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),

        // --- Type ---
        Text('Type', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _types.map((t) => ChoiceChip(
                label: Text(t),
                selected: _type == t,
                onSelected: (_) => setState(() => _type = t),
              )).toList(),
        ),
        const SizedBox(height: 16),

        // --- Description ---
        TextField(
          controller: _descController,
          maxLines: _type == 'memorize' ? 4 : 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Description',
            hintText: _type == 'memorize' ? 'Paste verse text here' : 'Optional description',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // --- Type-specific config ---
        ..._buildTypeConfig(theme, colorScheme),

        // --- Categories ---
        Text('Category', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            // Presets
            ..._presetCategories.map((c) => FilterChip(
                  label: Text(c),
                  selected: _selectedCategories.contains(c),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _selectedCategories.add(c);
                    } else {
                      _selectedCategories.remove(c);
                    }
                  }),
                )),
            // Existing categories from user's practices (not in presets)
            ...widget.existingCategories
                .where((c) => !_presetCategories.contains(c))
                .map((c) => FilterChip(
                      label: Text(c),
                      selected: _selectedCategories.contains(c),
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          _selectedCategories.add(c);
                        } else {
                          _selectedCategories.remove(c);
                        }
                      }),
                    )),
          ],
        ),
        const SizedBox(height: 16),

        // --- Dates ---
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Start date',
                value: _startDate,
                onTap: () => _pickDate(true),
                onClear: () => setState(() => _startDate = null),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DateField(
                label: 'End date',
                value: _endDate,
                onTap: () => _pickDate(false),
                onClear: () => setState(() => _endDate = null),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // --- Error ---
        if (_error != null) ...[
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
          const SizedBox(height: 8),
        ],

        // --- Buttons ---
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.onCancel != null)
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed:
                  _submitting || _nameController.text.trim().isEmpty ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create'),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildTypeConfig(ThemeData theme, ColorScheme colorScheme) {
    switch (_type) {
      case 'tracker':
        return [
          Row(
            children: [
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Target Sets',
                    border: OutlineInputBorder(),
                  ),
                  controller: TextEditingController(text: '$_targetSets'),
                  onChanged: (v) => _targetSets = int.tryParse(v) ?? _targetSets,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Target Reps',
                    border: OutlineInputBorder(),
                  ),
                  controller: TextEditingController(text: '$_targetReps'),
                  onChanged: (v) => _targetReps = int.tryParse(v) ?? _targetReps,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _unit,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    border: OutlineInputBorder(),
                  ),
                  items: _units
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => setState(() => _unit = v ?? 'reps'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ];

      case 'memorize':
        return [
          Row(
            children: [
              const Text('Daily reps: '),
              SizedBox(
                width: 60,
                child: TextField(
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  controller: TextEditingController(text: '$_dailyReps'),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n >= 1 && n <= 20) _dailyReps = n;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ];

      case 'scheduled':
        return [
          Text('Schedule', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          // Schedule type selector
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('Every N days'),
                selected: _scheduleType == 'interval',
                onSelected: (_) => setState(() => _scheduleType = 'interval'),
              ),
              ChoiceChip(
                label: const Text('Multiple/day'),
                selected: _scheduleType == 'daily_slots',
                onSelected: (_) => setState(() => _scheduleType = 'daily_slots'),
              ),
              ChoiceChip(
                label: const Text('Weekly'),
                selected: _scheduleType == 'weekly',
                onSelected: (_) => setState(() => _scheduleType = 'weekly'),
              ),
              ChoiceChip(
                label: const Text('Monthly'),
                selected: _scheduleType == 'monthly',
                onSelected: (_) => setState(() => _scheduleType = 'monthly'),
              ),
              ChoiceChip(
                label: const Text('One-time'),
                selected: _scheduleType == 'once',
                onSelected: (_) => setState(() => _scheduleType = 'once'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Schedule-type-specific fields
          ..._buildScheduleFields(theme, colorScheme),
          const SizedBox(height: 16),
        ];

      default:
        return [];
    }
  }

  List<Widget> _buildScheduleFields(ThemeData theme, ColorScheme colorScheme) {
    switch (_scheduleType) {
      case 'interval':
        return [
          Row(
            children: [
              const Text('Every '),
              SizedBox(
                width: 60,
                child: TextField(
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  controller: TextEditingController(text: '$_intervalDays'),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n >= 1) _intervalDays = n;
                  },
                ),
              ),
              const Text(' days'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: _shiftOnEarly,
                onChanged: (v) => setState(() => _shiftOnEarly = v ?? true),
              ),
              const Flexible(child: Text('Shift schedule if done early')),
            ],
          ),
        ];

      case 'daily_slots':
        return [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _dailySlots
                .map((s) => Chip(
                      label: Text(s),
                      onDeleted: () => setState(() => _dailySlots.remove(s)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _slotController,
                  decoration: const InputDecoration(
                    hintText: 'Add slot (e.g. lunch)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onSubmitted: (v) {
                    final trimmed = v.trim();
                    if (trimmed.isNotEmpty && !_dailySlots.contains(trimmed)) {
                      setState(() => _dailySlots.add(trimmed));
                      _slotController.clear();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  final trimmed = _slotController.text.trim();
                  if (trimmed.isNotEmpty && !_dailySlots.contains(trimmed)) {
                    setState(() => _dailySlots.add(trimmed));
                    _slotController.clear();
                  }
                },
              ),
            ],
          ),
        ];

      case 'weekly':
        return [
          Wrap(
            spacing: 4,
            children: _weekDays
                .map((d) => FilterChip(
                      label: Text(d),
                      selected: _weeklyDays.contains(d.toLowerCase()),
                      onSelected: (sel) => setState(() {
                        final key = d.toLowerCase();
                        sel ? _weeklyDays.add(key) : _weeklyDays.remove(key);
                      }),
                    ))
                .toList(),
          ),
        ];

      case 'monthly':
        return [
          Row(
            children: [
              const Text('Day of month: '),
              SizedBox(
                width: 60,
                child: TextField(
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  controller: TextEditingController(text: '$_monthlyDay'),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n >= 1 && n <= 31) _monthlyDay = n;
                  },
                ),
              ),
            ],
          ),
        ];

      case 'once':
        return [
          InkWell(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: now,
                firstDate: now,
                lastDate: DateTime(now.year + 5),
              );
              if (picked != null && mounted) {
                setState(() {
                  _onceDueDate =
                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                });
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Due date',
                border: OutlineInputBorder(),
              ),
              child: Text(
                _onceDueDate ?? 'Pick a date',
                style: _onceDueDate == null
                    ? TextStyle(color: theme.colorScheme.outline)
                    : null,
              ),
            ),
          ),
        ];

      default:
        return [];
    }
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: value != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: onClear,
                )
              : null,
        ),
        child: Text(
          value ?? 'Optional',
          style: value == null
              ? TextStyle(color: Theme.of(context).colorScheme.outline)
              : null,
        ),
      ),
    );
  }
}
