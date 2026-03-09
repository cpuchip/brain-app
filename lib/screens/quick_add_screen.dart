import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/brain_api.dart';
import '../services/brain_service.dart';
import '../services/speech_service.dart';
import '../services/widget_service.dart';

/// Transparent overlay screen launched from the home widget.
///
/// Two modes:
/// - **text**: keyboard auto-focused for typing
/// - **voice**: STT auto-starts for voice capture
class QuickAddScreen extends StatefulWidget {
  final String mode; // 'text' or 'voice'
  final BrainApi api;

  const QuickAddScreen({super.key, required this.mode, required this.api});

  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  final _textCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _speechService = SpeechService();

  bool _sending = false;
  bool _listening = false;
  bool _speechReady = false;
  String _partialText = '';
  String _category = 'inbox';

  static const _categories = ['inbox', 'actions', 'ideas', 'journal'];

  @override
  void initState() {
    super.initState();
    _speechService.onResult = _onSpeechResult;
    _speechService.onListeningChanged = (listening) {
      if (mounted) setState(() => _listening = listening);
    };
    _speechService.onError = (error) {
      if (mounted) {
        setState(() => _listening = false);
      }
    };

    if (widget.mode == 'voice') {
      _initAndListen();
    } else {
      // Text mode — focus the field after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  Future<void> _initAndListen() async {
    await _speechService.init();
    if (!mounted) return;
    setState(() => _speechReady = true);
    await _speechService.startListening();
  }

  void _onSpeechResult(String text, bool isFinal) {
    if (!mounted) return;
    if (isFinal) {
      // Append final result to text field
      final current = _textCtrl.text;
      final sep = current.isEmpty ? '' : ' ';
      _textCtrl.text = '$current$sep$text';
      _textCtrl.selection = TextSelection.collapsed(offset: _textCtrl.text.length);
      setState(() => _partialText = '');
    } else {
      setState(() => _partialText = text);
    }
  }

  Future<void> _toggleListening() async {
    if (!_speechReady) {
      await _speechService.init();
      if (!mounted) return;
      setState(() => _speechReady = true);
    }
    await _speechService.toggleListening();
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      final entry = await widget.api.createEntry(
        title: text,
        body: '',
        category: _category,
      );
      // Fire-and-forget: trigger AI classification in direct mode
      if (widget.api.hasBrainUrl) {
        widget.api.classifyEntry(entry.id).catchError((_) => null);
      }
      // Save to recent_thoughts so capture tab picks it up
      await _saveToRecentThoughts(text, entry);
      // Refresh widget data so the new entry appears
      try {
        final entries = await widget.api.getHistory(limit: 50);
        await WidgetService().updateWidget(entries);
      } catch (_) {}
      if (mounted) _dismiss();
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create: $e')),
        );
      }
    }
  }

  /// Persist to recent_thoughts so the main app's capture tab sees it.
  Future<void> _saveToRecentThoughts(String text, HistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('recent_thoughts');
    List<Map<String, dynamic>> existing = [];
    if (raw != null) {
      try {
        existing = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    final thought = PendingThought(
      id: entry.id,
      text: text,
      timestamp: DateTime.now(),
      sent: true,
      result: BrainResult(
        thoughtId: entry.id,
        entryId: entry.id,
        category: entry.category ?? 'inbox',
        title: entry.title ?? text,
        confidence: entry.confidence ?? 0.0,
        tags: entry.tags,
      ),
    );
    existing.insert(0, thought.toJson());
    if (existing.length > 20) existing = existing.sublist(0, 20);
    await prefs.setString('recent_thoughts', jsonEncode(existing));
  }

  void _dismiss() {
    SystemNavigator.pop();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _focusNode.dispose();
    _speechService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      onTap: _dismiss,
      child: Scaffold(
        backgroundColor: Colors.black54,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // Bottom card, anchored above keyboard
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset,
              child: GestureDetector(
                onTap: () {}, // absorb taps so scrim doesn't dismiss
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + MediaQuery.of(context).viewPadding.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Text field + mic toggle
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _textCtrl,
                              focusNode: _focusNode,
                              autofocus: widget.mode == 'text',
                              textCapitalization:
                                  TextCapitalization.sentences,
                              maxLines: 3,
                              minLines: 1,
                              decoration: InputDecoration(
                                hintText: _listening
                                    ? 'Listening…'
                                    : 'What\'s on your mind?',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _toggleListening,
                            icon: Icon(
                              _listening ? Icons.mic : Icons.mic_none,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: _listening
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                              foregroundColor: _listening
                                  ? Theme.of(context).colorScheme.onError
                                  : Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),

                      // Partial speech preview
                      if (_partialText.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _partialText,
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.5),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Category chips
                      Wrap(
                        spacing: 8,
                        children: _categories.map((cat) {
                          final selected = cat == _category;
                          return ChoiceChip(
                            label: Text(cat),
                            selected: selected,
                            onSelected: (_) =>
                                setState(() => _category = cat),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 12),

                      // Send button
                      FilledButton.icon(
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: Text(_sending ? 'Sending…' : 'Send'),
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
