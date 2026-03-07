import 'package:flutter/material.dart';
import '../services/brain_api.dart';

/// Full-screen form for creating a new brain entry.
class CreateEntryScreen extends StatefulWidget {
  final BrainApi api;

  const CreateEntryScreen({super.key, required this.api});

  @override
  State<CreateEntryScreen> createState() => _CreateEntryScreenState();
}

class _CreateEntryScreenState extends State<CreateEntryScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _dueDateCtrl = TextEditingController();
  final _nextActionCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  String _category = 'inbox';
  String _status = '';

  bool _saving = false;
  bool _dirty = false;

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
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Title is required'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await widget.api.createEntry(
        title: title,
        body: body.isEmpty ? title : body,
        category: _category,
        status: _status.isNotEmpty ? _status : null,
        dueDate: _dueDateCtrl.text.trim().isNotEmpty ? _dueDateCtrl.text.trim() : null,
        nextAction: _nextActionCtrl.text.trim().isNotEmpty ? _nextActionCtrl.text.trim() : null,
        tags: _tagsCtrl.text.trim().isNotEmpty
            ? _tagsCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
            : null,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Create failed: $e'),
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
        title: const Text('Discard entry?'),
        content: const Text('You have unsaved changes.'),
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
          title: const Text('New Entry'),
          actions: [
            TextButton.icon(
              onPressed: (_saving || _titleCtrl.text.trim().isEmpty) ? null : _save,
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
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _category,
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
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        hintText: 'active, waiting...',
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

              TextField(
                controller: _tagsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: 'tag1, tag2, tag3',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
