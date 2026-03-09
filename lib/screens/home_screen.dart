import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import '../services/brain_service.dart';
import '../services/brain_api.dart';
import '../services/becoming_api.dart';
import '../services/speech_service.dart';
import '../services/notification_service.dart';
import '../services/offline_queue.dart';
import '../services/widget_service.dart';
import '../services/error_log_service.dart';
import '../widgets/thought_card.dart';
import '../widgets/connection_indicator.dart';
import 'create_entry_screen.dart';
import 'edit_entry_screen.dart';
import 'history_screen.dart';
import 'today_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final String url;
  final String token;
  final String brainUrl;
  final Future<void> Function(String url, String token, String brainUrl) onSettingsChanged;

  const HomeScreen({
    super.key,
    required this.url,
    required this.token,
    this.brainUrl = '',
    required this.onSettingsChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late BrainService _brain;
  late BrainApi _api;
  late BecomingApi _becomingApi;
  final SpeechService _speech = SpeechService();
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _todayKey = GlobalKey<TodayScreenState>();

  BrainConnectionState _connectionState = BrainConnectionState.disconnected;
  bool _agentOnline = false;
  bool _isListening = false;
  final List<PendingThought> _thoughts = [];
  int _tabIndex = 0;

  // STT preferences
  bool _autoSend = true;
  bool _drivingMode = false;

  // Offline queue
  final _offlineQueue = OfflineQueue();
  int _queueCount = 0;
  int _wsErrorCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textController.addListener(() => setState(() {}));
    _loadSttPrefs();
    _initServices();
    _initSpeech();
    _initNotifications();
    _initOfflineQueue();
    _initWidgetClicks();
  }

  void _initWidgetClicks() {
    HomeWidget.widgetClicked.listen((uri) {
      if (uri == null) return;
      if (uri.host == 'voice') {
        // Focus text field and start listening
        _focusNode.requestFocus();
        _speech.startListening();
      } else if (uri.host == 'refresh') {
        // Widget refresh button — just trigger a widget data update
        _updateWidget();
      } else if (uri.host == 'entry' && uri.pathSegments.isNotEmpty) {
        final entryId = uri.pathSegments.first;
        _openEntryById(entryId);
      } else if (uri.host == 'done' && uri.pathSegments.isNotEmpty) {
        final entryId = uri.pathSegments.first;
        _markDoneById(entryId);
      } else if (uri.host == 'create') {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CreateEntryScreen(api: _api),
          ),
        );
      }
    });
  }

  Future<void> _markDoneById(String entryId) async {
    try {
      final entries = await _api.getHistory(limit: 50);
      final entry = entries.cast<HistoryEntry?>().firstWhere(
        (e) => e!.id == entryId,
        orElse: () => null,
      );
      if (entry != null) {
        await _api.toggleDone(entry);
        await _updateWidget();
      }
    } catch (_) {}
  }

  Future<void> _openEntryById(String entryId) async {
    try {
      final entries = await _api.getHistory(limit: 50);
      final entry = entries.cast<HistoryEntry?>().firstWhere(
        (e) => e!.id == entryId,
        orElse: () => null,
      );
      if (entry != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditEntryScreen(
              api: _api,
              entry: entry,
              entryUpdated: _brain.entryUpdated,
            ),
          ),
        );
      }
    } catch (_) {}
  }

  void _initNotifications() {
    final notifs = NotificationService();
    notifs.onNotificationAction = (entryId, actionId) async {
      switch (actionId) {
        case 'mark_done':
          try {
            // Find entry type to toggle correctly
            final entries = await _api.getHistory(limit: 50);
            final entry = entries.cast<HistoryEntry?>().firstWhere(
              (e) => e!.id == entryId,
              orElse: () => null,
            );
            if (entry != null) {
              await _api.toggleDone(entry);
              notifs.cancelReminder(entryId);
            }
          } catch (_) {}
        case 'snooze':
          notifs.snoozeReminder(entryId, null, const Duration(hours: 1));
        default:
          // Open entry for editing
          try {
            final entries = await _api.getHistory(limit: 50);
            final entry = entries.cast<HistoryEntry?>().firstWhere(
              (e) => e!.id == entryId,
              orElse: () => null,
            );
            if (entry != null && mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditEntryScreen(
                    api: _api,
                    entry: entry,
                    entryUpdated: _brain.entryUpdated,
                  ),
                ),
              );
            }
          } catch (_) {}
      }
    };
  }

  void _initOfflineQueue() {
    _offlineQueue.startMonitoring(_brain, _api);
    _offlineQueue.onCountChanged = (count) {
      if (mounted) setState(() => _queueCount = count);
    };
    _offlineQueue.onSynced = () {
      // Refresh widget data after sync drain
      _updateWidget();
    };
    // Check initial count
    _offlineQueue.count().then((c) {
      if (mounted) setState(() => _queueCount = c);
    });
  }

  Future<void> _updateWidget() async {
    try {
      final entries = await _api.getHistory(limit: 50);
      await WidgetService().updateWidget(entries);
    } catch (_) {}
  }

  Future<void> _loadSttPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoSend = prefs.getBool('stt_auto_send') ?? true;
        _drivingMode = prefs.getBool('stt_driving_mode') ?? false;
      });
    }
  }

  Future<void> _initSpeech() async {
    _speech.onResult = (text, isFinal) {
      if (mounted) {
        setState(() {
          _textController.text = text;
          _textController.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
        });
        // Auto-send on final result if enabled
        if (isFinal && text.trim().isNotEmpty && _autoSend) {
          _sendThought();
        }
      }
    };
    _speech.onListeningChanged = (listening) {
      if (mounted) setState(() => _isListening = listening);
    };
    _speech.onError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voice: $error'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    };
    await _speech.init();
  }

  void _initServices() {
    _brain = BrainService(baseUrl: widget.url, token: widget.token);
    _api = BrainApi(
      baseUrl: widget.url,
      token: widget.token,
      brainUrl: widget.brainUrl.isNotEmpty ? widget.brainUrl : null,
    );
    _becomingApi = BecomingApi(baseUrl: widget.url, token: widget.token);

    _brain.onError = (error) {
      ErrorLogService().log('websocket', error);
      _wsErrorCount++;
      // Only show snackbar for the first connection error, not repeated reconnect noise
      if (_wsErrorCount <= 1 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    };

    _brain.onStateChanged = (state) {
      if (mounted) setState(() => _connectionState = state);
      // Reset error count when successfully connected
      if (state == BrainConnectionState.connected) {
        _wsErrorCount = 0;
      }
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
        // Speak back the result in driving mode
        if (_drivingMode) {
          _speech.speak(
            '${result.category}: ${result.title}',
          );
        }
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
    _speech.dispose();
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendThought() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (_connectionState == BrainConnectionState.connected) {
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
    } else {
      // Offline: queue for later
      _offlineQueue.enqueue('thought', {'text': text});
      setState(() {
        _thoughts.insert(
          0,
          PendingThought(
            id: 'offline_${DateTime.now().millisecondsSinceEpoch}',
            text: text,
            timestamp: DateTime.now(),
            sent: false,
            error: 'Queued offline',
          ),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved offline — will sync when connected'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    _textController.clear();
    _focusNode.requestFocus();
    HapticFeedback.lightImpact();

    // In driving mode, restart mic after sending
    if (_drivingMode) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_isListening) {
          _speech.startListening();
        }
      });
    }

    // Scroll to top to show new thought
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _editThought(PendingThought thought) async {
    final result = thought.result;
    if (result == null) return;

    HistoryEntry? entry;

    // If we have an entry ID from the result, construct directly
    if (result.entryId != null && result.entryId!.isNotEmpty) {
      entry = HistoryEntry(
        id: result.entryId!,
        text: thought.text,
        category: result.category,
        title: result.title,
        confidence: result.confidence,
        timestamp: thought.timestamp,
        processed: true,
        tags: result.tags,
      );
    } else {
      // Fetch recent entries and match by title + approximate timestamp
      try {
        final entries = await _api.getHistory(limit: 20);
        entry = entries.cast<HistoryEntry?>().firstWhere(
          (e) => e!.title == result.title && e.category == result.category,
          orElse: () => null,
        );
      } catch (_) {
        // Fall through to error below
      }
    }

    if (!mounted) return;

    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entry still syncing — try again in a moment'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditEntryScreen(
          api: _api,
          entry: entry!,
          entryUpdated: _brain.entryUpdated,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              _tabIndex == 0
                  ? Icons.psychology
                  : _tabIndex == 1
                      ? Icons.today
                      : Icons.history,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(_tabIndex == 0
                ? 'Brain'
                : _tabIndex == 1
                    ? 'Today'
                    : 'History'),
          ],
        ),
        actions: [
          ConnectionIndicator(
            connectionState: _connectionState,
            agentOnline: _agentOnline,
            queueCount: _queueCount,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    initialUrl: widget.url,
                    initialToken: widget.token,
                    initialBrainUrl: widget.brainUrl,
                    onSaved: widget.onSettingsChanged,
                  ),
                ),
              );
              _loadSttPrefs();
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          // Tab 0: Capture (original home body)
          _buildCaptureTab(theme, colorScheme),
          // Tab 1: Today
          TodayScreen(
            key: _todayKey,
            becomingApi: _becomingApi,
            brainApi: _api,
            entryUpdated: _brain.entryUpdated,
          ),
          // Tab 2: History
          HistoryScreen(
            api: _api,
            entryUpdated: _brain.entryUpdated,
            embedded: true,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) {
          setState(() => _tabIndex = index);
          if (index == 1) {
            _todayKey.currentState?.refresh();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'Capture',
          ),
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureTab(ThemeData theme, ColorScheme colorScheme) {
    return Column(
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
                    final thought = _thoughts[index];
                    return ThoughtCard(
                      thought: thought,
                      onEdit: thought.result != null
                          ? () => _editThought(thought)
                          : null,
                    );
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
          padding: const EdgeInsets.only(
            left: 16,
            right: 8,
            top: 8,
            bottom: 8,
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
              const SizedBox(width: 4),
              // Mic button — hold or tap to toggle
              GestureDetector(
                onLongPressStart: (_) => _speech.startListening(),
                onLongPressEnd: (_) => _speech.stopListening(),
                child: IconButton(
                  onPressed: () => _speech.toggleListening(),
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  tooltip: _isListening ? 'Stop listening' : 'Voice capture',
                ),
              ),
              const SizedBox(width: 4),
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
    );
  }
}
