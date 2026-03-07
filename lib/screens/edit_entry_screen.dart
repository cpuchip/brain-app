import 'package:flutter/material.dart';
import '../services/brain_api.dart';

/// Full-screen editor for a brain entry.
class EditEntryScreen extends StatefulWidget {
  final BrainApi api;
  final HistoryEntry entry;

  const EditEntryScreen({super.key, required this.api, required this.entry});

  @override
  State<EditEntryScreen> createState() => _EditEntryScreenState();
}

class _EditEntryScreenState extends State<EditEntryScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _bodyCtrl;
  late TextEditingController _dueDateCtrl;
  late TextEditingController _nextActionCtrl;
  late TextEditingController _tagsCtrl;
  late String _category;
  late String _status;

  bool _saving = false;
  bool _dirty = false;
  bool _classifying = false;

  static const _categories = [
    'inbox',
    'actions',
    'projects',
    'ideas',
    'people',
    'study',
    'journal',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleCtrl = TextEditingController(text: e.title ?? '');
    _bodyCtrl = TextEditingController(text: e.text);
    _dueDateCtrl = TextEditingController(text: e.dueDate ?? '');
    _nextActionCtrl = TextEditingController(text: e.nextAction ?? '');
    _tagsCtrl = TextEditingController(text: e.tags.join(', '));
    _category = e.category ?? 'inbox';
    _status = e.status ?? '';

    for (final c in [_titleCtrl, _bodyCtrl, _dueDateCtrl, _nextActionCtrl, _tagsCtrl]) {
      c.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _dueDateCtrl.dispose();
    _nextActionCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final updates = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'body': _bodyCtrl.text.trim(),
      'category': _category,
      'due_date': _dueDateCtrl.text.trim().isEmpty ? null : _dueDateCtrl.text.trim(),
      'next_action': _nextActionCtrl.text.trim().isEmpty ? null : _nextActionCtrl.text.trim(),
      'tags': _tagsCtrl.text.trim().isEmpty
          ? <String>[]
          : _tagsCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
    };

    if (_status.isNotEmpty) {
      updates['status'] = _status;
    }

    try {
      await widget.api.updateEntry(widget.entry.id, updates);
      if (mounted) {
        Navigator.pop(context, true); // true = changed
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _classify() async {
    if (!widget.api.hasBrainUrl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set Brain URL in Settings to use AI classification'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _classifying = true);
    try {
      final updated = await widget.api.classifyEntry(widget.entry.id);
      if (mounted && updated != null) {
        // Refresh form fields from classification results
        _titleCtrl.text = updated.title ?? _titleCtrl.text;
        _bodyCtrl.text = updated.text.isNotEmpty ? updated.text : _bodyCtrl.text;
        _dueDateCtrl.text = updated.dueDate ?? '';
        _nextActionCtrl.text = updated.nextAction ?? '';
        _tagsCtrl.text = updated.tags.join(', ');
        setState(() {
          _category = updated.category ?? _category;
          _classifying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Classified as "${updated.category}" — ${updated.title}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _classifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Classify failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_dueDateCtrl.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      _dueDateCtrl.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _markDirty();
    }
  }

  Future<bool> _onWillPop() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved edits.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _onWillPop()) {
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Entry'),
          actions: [
            IconButton(
                onPressed: _classifying ? null : _classify,
                icon: _classifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high),
                tooltip: 'AI Classify',
              ),
            TextButton.icon(
              onPressed: (_saving || !_dirty) ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Save'),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),

              // Category + Status row
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _categories.contains(_category) ? _category : 'inbox',
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: _categories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _category = v;
                            _dirty = true;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _status)
                        ..addListener(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        hintText: 'active, done, waiting...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        _status = v;
                        _markDirty();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Body
              TextField(
                controller: _bodyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Body',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 6,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),

              // Due date + Next action row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dueDateCtrl,
                      decoration: InputDecoration(
                        labelText: 'Due Date',
                        hintText: 'YYYY-MM-DD',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today, size: 20),
                          onPressed: _pickDate,
                        ),
                      ),
                      readOnly: true,
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _nextActionCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Next Action',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tags
              TextField(
                controller: _tagsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: 'tag1, tag2, tag3',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // Done toggle for actionable entries
              if (widget.entry.isActionable)
                SwitchListTile(
                  title: const Text('Mark as done'),
                  subtitle: Text(widget.entry.category == 'actions'
                      ? 'Action completed'
                      : 'Project finished'),
                  value: widget.entry.isDone,
                  onChanged: (v) async {
                    try {
                      await widget.api.toggleDone(widget.entry);
                      if (!context.mounted) return;
                      Navigator.pop(context, true);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e'), behavior: SnackBarBehavior.floating),
                      );
                    }
                  },
                  tileColor: colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
