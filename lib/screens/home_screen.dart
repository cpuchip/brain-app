import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/brain_service.dart';
import '../services/brain_api.dart';
import '../widgets/thought_card.dart';
import '../widgets/connection_indicator.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final String url;
  final String token;
  final Future<void> Function(String url, String token) onSettingsChanged;

  const HomeScreen({
    super.key,
    required this.url,
    required this.token,
    required this.onSettingsChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late BrainService _brain;
  late BrainApi _api;
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  BrainConnectionState _connectionState = BrainConnectionState.disconnected;
  bool _agentOnline = false;
  final List<PendingThought> _thoughts = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textController.addListener(() => setState(() {}));
    _initServices();
  }

  void _initServices() {
    _brain = BrainService(baseUrl: widget.url, token: widget.token);
    _api = BrainApi(baseUrl: widget.url, token: widget.token);

    _brain.onStateChanged = (state) {
      if (mounted) setState(() => _connectionState = state);
    };

    _brain.onAgentPresence = (online) {
      if (mounted) setState(() => _agentOnline = online);
    };

    _brain.onResult = (result) {
      if (mounted) {
        setState(() {
          // Find matching pending thought and attach result
          for (final t in _thoughts) {
            if (t.id == result.thoughtId) {
              t.result = result;
              break;
            }
          }
        });
      }
    };

    _brain.onError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    };

    _brain.connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_connectionState == BrainConnectionState.disconnected) {
        _brain.connect();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _brain.dispose();
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendThought() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final id = _brain.sendThought(text);
    setState(() {
      _thoughts.insert(
        0,
        PendingThought(
          id: id,
          text: text,
          timestamp: DateTime.now(),
          sent: true,
        ),
      );
    });

    _textController.clear();
    _focusNode.requestFocus();
    HapticFeedback.lightImpact();

    // Scroll to top to show new thought
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.psychology, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Brain'),
          ],
        ),
        actions: [
          ConnectionIndicator(
            connectionState: _connectionState,
            agentOnline: _agentOnline,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => HistoryScreen(api: _api),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    initialUrl: widget.url,
                    initialToken: widget.token,
                    onSaved: widget.onSettingsChanged,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Thought list
          Expanded(
            child: _thoughts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: 64,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Capture a thought',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Type below — your brain will classify it',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _thoughts.length,
                    itemBuilder: (context, index) {
                      return ThoughtCard(thought: _thoughts[index]);
                    },
                  ),
          ),

          // Input bar
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: EdgeInsets.only(
              left: 16,
              right: 8,
              top: 8,
              bottom: MediaQuery.of(context).viewPadding.bottom + 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.send,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 4,
                    minLines: 1,
                    onSubmitted: (_) => _sendThought(),
                    decoration: InputDecoration(
                      hintText: 'What\'s on your mind?',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  onPressed: _textController.text.trim().isEmpty
                      ? null
                      : _sendThought,
                  elevation: 0,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
