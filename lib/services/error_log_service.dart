import 'dart:collection';

/// A single error log entry.
class ErrorEntry {
  final DateTime timestamp;
  final String source;
  final String message;

  ErrorEntry({
    required this.timestamp,
    required this.source,
    required this.message,
  });

  String get formatted =>
      '[${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}] $source: $message';
}

/// Singleton service that captures recent errors for debugging.
class ErrorLogService {
  static final ErrorLogService _instance = ErrorLogService._();
  factory ErrorLogService() => _instance;
  ErrorLogService._();

  static const _maxEntries = 100;
  final _entries = Queue<ErrorEntry>();

  /// All logged errors, newest first.
  List<ErrorEntry> get entries => _entries.toList().reversed.toList();

  int get count => _entries.length;

  /// Log an error from a named source.
  void log(String source, String message) {
    _entries.addLast(ErrorEntry(
      timestamp: DateTime.now(),
      source: source,
      message: message,
    ));
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
  }

  void clear() => _entries.clear();

  /// All entries as a single string for copying.
  String export() => entries.map((e) => e.formatted).join('\n');
}
