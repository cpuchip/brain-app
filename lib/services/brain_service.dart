import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Message types matching the brain relay protocol.
class MessageType {
  static const auth = 'auth';
  static const authOk = 'auth_ok';
  static const authError = 'auth_error';
  static const thought = 'thought';
  static const result = 'result';
  static const status = 'status';
  static const ping = 'ping';
  static const pong = 'pong';
  static const presence = 'presence';
  static const entryUpdated = 'entry_updated';
  static const entriesRequest = 'entries_request';
  static const entriesResponse = 'entries_response';
  static const queued = 'queued';
}

/// A classified result from the brain agent.
class BrainResult {
  final String thoughtId;
  final String? entryId;
  final String category;
  final String title;
  final double confidence;
  final List<String> tags;
  final bool needsReview;
  final String? filePath;

  BrainResult({
    required this.thoughtId,
    this.entryId,
    required this.category,
    required this.title,
    required this.confidence,
    this.tags = const [],
    this.needsReview = false,
    this.filePath,
  });

  factory BrainResult.fromJson(Map<String, dynamic> json) {
    return BrainResult(
      thoughtId: json['thought_id'] ?? '',
      entryId: json['entry_id']?.toString(),
      category: json['category'] ?? 'inbox',
      title: json['title'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      tags: List<String>.from(json['tags'] ?? []),
      needsReview: json['needs_review'] ?? false,
      filePath: json['file_path'],
    );
  }
}

/// A thought waiting to be sent.
class PendingThought {
  final String id;
  final String text;
  final DateTime timestamp;
  BrainResult? result;
  bool sent;
  String? error;

  PendingThought({
    required this.id,
    required this.text,
    required this.timestamp,
    this.result,
    this.sent = false,
    this.error,
  });
}

/// Connection state.
enum BrainConnectionState { disconnected, connecting, authenticating, connected }

/// WebSocket client for the brain relay protocol.
class BrainService {
  final String baseUrl; // e.g. "https://ibeco.me"
  final String token;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  BrainConnectionState _state = BrainConnectionState.disconnected;
  bool _agentOnline = false;
  bool _intentionalClose = false;
  int _reconnectAttempt = 0;

  // Stream for entry_updated events — screens subscribe to this.
  final _entryUpdatedController = StreamController<EntryUpdatedEvent>.broadcast();
  Stream<EntryUpdatedEvent> get entryUpdated => _entryUpdatedController.stream;

  // Callbacks
  void Function(BrainConnectionState state)? onStateChanged;
  void Function(bool online)? onAgentPresence;
  void Function(BrainResult result)? onResult;
  void Function(EntryUpdatedEvent event)? onEntryUpdated;
  void Function(List<Map<String, dynamic>> entries)? onEntriesSync;
  void Function(String error)? onError;

  BrainService({required this.baseUrl, required this.token});

  BrainConnectionState get state => _state;
  bool get agentOnline => _agentOnline;
  bool get isConnected => _state == BrainConnectionState.connected;

  /// Connect to the relay hub.
  void connect() {
    if (_state != BrainConnectionState.disconnected) return;
    _intentionalClose = false;
    _doConnect();
  }

  void _doConnect() {
    _setState(BrainConnectionState.connecting);

    final wsUrl = baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final uri = Uri.parse('$wsUrl/ws/brain');

    try {
      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: (error) {
          onError?.call('WebSocket error: $error');
          _onDisconnected();
        },
      );

      // Send auth
      _setState(BrainConnectionState.authenticating);
      _send({
        'type': MessageType.auth,
        'token': token,
        'role': 'app',
      });
    } catch (e) {
      onError?.call('Connection failed: $e');
      _scheduleReconnect();
    }
  }

  /// Send a thought for classification.
  String sendThought(String text) {
    final id = _generateId();
    _send({
      'type': MessageType.thought,
      'id': id,
      'text': text,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'source': 'app',
    });
    return id;
  }

  /// Disconnect from the relay.
  void disconnect() {
    _intentionalClose = true;
    _cleanup();
    _setState(BrainConnectionState.disconnected);
  }

  void _onMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      _handleMessage(json);
    } catch (e) {
      onError?.call('Parse error: $e');
    }
  }

  void _handleMessage(Map<String, dynamic> json) {
      final type = json['type'] as String?;

      switch (type) {
        case MessageType.authOk:
          _setState(BrainConnectionState.connected);
          _reconnectAttempt = 0;
          _startPingTimer();
          // Request cached entries from relay for fresh data on connect
          _send({'type': MessageType.entriesRequest});
          break;

        case MessageType.authError:
          onError?.call('Auth failed: ${json['error']}');
          _intentionalClose = true;
          _cleanup();
          _setState(BrainConnectionState.disconnected);
          break;

        case MessageType.result:
          final result = BrainResult.fromJson(json);
          onResult?.call(result);
          break;

        case MessageType.presence:
          _agentOnline = json['agent_online'] ?? false;
          onAgentPresence?.call(_agentOnline);
          break;

        case MessageType.entryUpdated:
          final entry = json['entry'] as Map<String, dynamic>?;
          if (entry != null) {
            final event = EntryUpdatedEvent.fromJson(entry);
            onEntryUpdated?.call(event);
            _entryUpdatedController.add(event);
          }
          break;

        case MessageType.entriesResponse:
          final entries = json['entries'] as List?;
          if (entries != null) {
            final mapped = entries
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            onEntriesSync?.call(mapped);
            // Also push each entry through the entryUpdated stream
            // so any open screens (HistoryScreen, EditEntryScreen) get updated
            for (final e in mapped) {
              final event = EntryUpdatedEvent.fromJson(e);
              _entryUpdatedController.add(event);
            }
          }
          break;

        case MessageType.queued:
          // Bundle of messages queued while offline — unwrap and process each
          final messages = json['messages'] as List?;
          if (messages != null) {
            for (final msg in messages) {
              if (msg is Map<String, dynamic>) {
                _handleMessage(msg);
              } else if (msg is Map) {
                _handleMessage(Map<String, dynamic>.from(msg));
              }
            }
          }
          break;

        case MessageType.ping:
          _send({'type': MessageType.pong});
          break;

        case MessageType.status:
          _agentOnline = json['agent_online'] ?? false;
          onAgentPresence?.call(_agentOnline);
          break;
      }
  }

  void _onDisconnected() {
    _cleanup();
    _setState(BrainConnectionState.disconnected);
    if (!_intentionalClose) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectAttempt++;
    final delay = Duration(
      seconds: _clamp(1 << _reconnectAttempt, 1, 30),
    );
    _reconnectTimer = Timer(delay, _doConnect);
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _send({'type': MessageType.ping});
    });
  }

  void _send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void _cleanup() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void _setState(BrainConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChanged?.call(newState);
  }

  String _generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hash = now.toRadixString(16).padLeft(8, '0');
    return hash + (now % 0xFFFF).toRadixString(16).padLeft(4, '0');
  }

  int _clamp(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  void dispose() {
    disconnect();
    _entryUpdatedController.close();
  }
}

/// Payload from an entry_updated WebSocket message.
/// Maps from the SyncEntryPayload format (uses 'body' not 'text').
class EntryUpdatedEvent {
  final String id;
  final String title;
  final String category;
  final String body;
  final String? status;
  final bool actionDone;
  final String? dueDate;
  final String? nextAction;
  final List<String> tags;
  final List<Map<String, dynamic>> subtasks;
  final String createdAt;
  final String updatedAt;

  EntryUpdatedEvent({
    required this.id,
    required this.title,
    required this.category,
    required this.body,
    this.status,
    this.actionDone = false,
    this.dueDate,
    this.nextAction,
    this.tags = const [],
    this.subtasks = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory EntryUpdatedEvent.fromJson(Map<String, dynamic> json) {
    return EntryUpdatedEvent(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      category: json['category'] ?? 'inbox',
      body: json['body'] ?? '',
      status: json['status'],
      actionDone: json['action_done'] ?? false,
      dueDate: json['due_date'],
      nextAction: json['next_action'],
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      subtasks: (json['subtasks'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
    );
  }
}
