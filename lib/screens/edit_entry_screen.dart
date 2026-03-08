import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/brain_api.dart';
import '../services/brain_service.dart';

/// Full-screen editor for a brain entry.
class EditEntryScreen extends StatefulWidget {
  final BrainApi api;
  final HistoryEntry entry;
  final Stream<EntryUpdatedEvent>? entryUpdated;

  const EditEntryScreen({
    super.key,
    required this.api,
    required this.entry,
    this.entryUpdated,
  });

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
  bool _previewBody = false;
  late List<SubTask> _subtasks;
  final TextEditingController _newSubTaskCtrl = TextEditingController();
  StreamSubscription<EntryUpdatedEvent>? _entryUpdatedSub;

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
    _subtasks = List<SubTask>.from(e.subtasks);

    for (final c in [_titleCtrl, _bodyCtrl, _dueDateCtrl, _nextActionCtrl, _tagsCtrl]) {
      c.addListener(_markDirty);
    }

    _entryUpdatedSub = widget.entryUpdated
        ?.where((e) => e.id == widget.entry.id)
        .listen(_onEntryUpdated);
  }

  void _onEntryUpdated(EntryUpdatedEvent event) {
    if (_dirty) {
      // User has local edits — show a snackbar instead of overwriting.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Entry was reclassified — save or discard to see changes'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    // No local edits — apply the update.
    _titleCtrl.text = event.title;
    _bodyCtrl.text = event.body;
    _dueDateCtrl.text = event.dueDate ?? '';
    _nextActionCtrl.text = event.nextAction ?? '';
    _tagsCtrl.text = event.tags.join(', ');
    setState(() {
      _category = event.category;
      _status = event.status ?? _status;
      _subtasks = event.subtasks.map((e) => SubTask.fromJson(e)).toList();
      _dirty = false; // reset since we just applied server state
      _classifying = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated — now "${event.category}": ${event.title}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _entryUpdatedSub?.cancel();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _dueDateCtrl.dispose();
    _nextActionCtrl.dispose();
    _tagsCtrl.dispose();
    _newSubTaskCtrl.dispose();
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
    setState(() => _classifying = true);
    try {
      final updated = await widget.api.classifyEntry(widget.entry.id);
      if (!mounted) return;
      if (updated != null) {
        // Direct mode: got synchronous result — refresh fields
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
      } else {
        // Relay mode: queued — result arrives async
        setState(() => _classifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Classification requested — refresh to see results'),
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

  // --- Sub-task actions ---

  Future<void> _addSubTask() async {
    final text = _newSubTaskCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      final st = await widget.api.createSubTask(widget.entry.id, text, sortOrder: _subtasks.length);
      setState(() {
        _subtasks.add(st);
        _newSubTaskCtrl.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Add failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _toggleSubTask(int index) async {
    final st = _subtasks[index];
    try {
      final updated = await widget.api.toggleSubTask(widget.entry.id, st);
      setState(() => _subtasks[index] = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Toggle failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _deleteSubTask(int index) async {
    final st = _subtasks[index];
    try {
      await widget.api.deleteSubTask(widget.entry.id, st.id);
      setState(() => _subtasks.removeAt(index));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
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

              // Body — edit / preview toggle
              Row(
                children: [
                  Text('Body', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Edit')),
                      ButtonSegment(value: true, label: Text('Preview')),
                    ],
                    selected: {_previewBody},
                    onSelectionChanged: (v) => setState(() => _previewBody = v.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_previewBody)
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 100),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _bodyCtrl.text.trim().isEmpty
                      ? Text('Nothing to preview',
                          style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.outline))
                      : MarkdownBody(
                          data: _bodyCtrl.text,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                            p: theme.textTheme.bodyMedium,
                          ),
                        ),
                )
              else
                TextField(
                  controller: _bodyCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 8,
                  minLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
              const SizedBox(height: 16),

              // Sub-tasks
              Text('Sub-tasks', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              if (_subtasks.isNotEmpty) ...[
                ...List.generate(_subtasks.length, (i) {
                  final st = _subtasks[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _toggleSubTask(i),
                          child: Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: st.done ? Colors.green.shade600 : Colors.transparent,
                              border: Border.all(
                                color: st.done ? Colors.green.shade600 : colorScheme.outline,
                                width: 2,
                              ),
                            ),
                            child: st.done
                                ? const Icon(Icons.check, size: 14, color: Colors.white)
                                : null,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            st.text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              decoration: st.done ? TextDecoration.lineThrough : null,
                              color: st.done ? colorScheme.outline : null,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, size: 18, color: colorScheme.outline),
                          onPressed: () => _deleteSubTask(i),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 4),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newSubTaskCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Add item...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _addSubTask(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _addSubTask,
                    icon: const Icon(Icons.add, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
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
