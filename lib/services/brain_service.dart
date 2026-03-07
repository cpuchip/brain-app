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

  // Callbacks
  void Function(BrainConnectionState state)? onStateChanged;
  void Function(bool online)? onAgentPresence;
  void Function(BrainResult result)? onResult;
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
      final type = json['type'] as String?;

      switch (type) {
        case MessageType.authOk:
          _setState(BrainConnectionState.connected);
          _reconnectAttempt = 0;
          _startPingTimer();
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

        case MessageType.ping:
          _send({'type': MessageType.pong});
          break;

        case MessageType.status:
          _agentOnline = json['agent_online'] ?? false;
          onAgentPresence?.call(_agentOnline);
          break;
      }
    } catch (e) {
      onError?.call('Parse error: $e');
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
  }
}
