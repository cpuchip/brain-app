import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'brain_api.dart';
import 'brain_service.dart';

/// Item in the offline queue.
class QueueItem {
  final int id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;

  QueueItem({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    required this.attempts,
  });
}

/// Offline queue — stores thoughts/mutations locally when no network,
/// drains automatically when connectivity returns.
class OfflineQueue {
  static final OfflineQueue _instance = OfflineQueue._();
  factory OfflineQueue() => _instance;
  OfflineQueue._();

  Database? _db;
  StreamSubscription? _connectivitySub;
  BrainService? _brain;
  BrainApi? _api;
  bool _draining = false;

  /// Callback when queue count changes.
  void Function(int count)? onCountChanged;

  /// Callback when an item is successfully synced.
  void Function()? onSynced;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/brain_queue.db',
      version: 1,
      onCreate: (db, v) => db.execute('''
        CREATE TABLE queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL,
          attempts INTEGER DEFAULT 0
        )
      '''),
    );
  }

  /// Start monitoring connectivity and draining when online.
  void startMonitoring(BrainService brain, BrainApi api) {
    _brain = brain;
    _api = api;
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        drainQueue();
      }
    });
  }

  /// Enqueue an operation for later sync.
  Future<void> enqueue(String type, Map<String, dynamic> payload) async {
    await _db?.insert('queue', {
      'type': type,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    final c = await count();
    onCountChanged?.call(c);
  }

  /// Get all pending items.
  Future<List<QueueItem>> pending() async {
    final rows = await _db?.query('queue', orderBy: 'id ASC') ?? [];
    return rows.map((row) => QueueItem(
      id: row['id'] as int,
      type: row['type'] as String,
      payload: jsonDecode(row['payload'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      attempts: row['attempts'] as int,
    )).toList();
  }

  /// Remove a successfully synced item.
  Future<void> dequeue(int id) async {
    await _db?.delete('queue', where: 'id = ?', whereArgs: [id]);
    final c = await count();
    onCountChanged?.call(c);
  }

  /// Increment attempt counter for a failed item.
  Future<void> incrementAttempts(int id) async {
    await _db?.rawUpdate(
      'UPDATE queue SET attempts = attempts + 1 WHERE id = ?',
      [id],
    );
  }

  /// Get pending count.
  Future<int> count() async {
    final result = await _db?.rawQuery('SELECT COUNT(*) as c FROM queue');
    return result?.first['c'] as int? ?? 0;
  }

  /// Drain the queue — attempt to sync all pending items.
  Future<void> drainQueue() async {
    if (_draining || _brain == null || _api == null) return;
    _draining = true;

    try {
      final items = await pending();
      for (final item in items) {
        if (item.attempts > 5) continue; // give up after 5 tries

        try {
          switch (item.type) {
            case 'thought':
              _brain!.sendThought(item.payload['text']);
            case 'entry_create':
              await _api!.createEntry(
                title: item.payload['title'] ?? '',
                body: item.payload['body'] ?? '',
                category: item.payload['category'] ?? 'inbox',
                status: item.payload['status'],
                dueDate: item.payload['due_date'],
                nextAction: item.payload['next_action'],
                tags: (item.payload['tags'] as List?)?.cast<String>(),
              );
            case 'entry_update':
              await _api!.updateEntry(
                item.payload['id'],
                Map<String, dynamic>.from(item.payload['updates']),
              );
            case 'entry_delete':
              await _api!.deleteEntry(item.payload['id']);
          }
          await dequeue(item.id);
          onSynced?.call();
        } catch (e) {
          await incrementAttempts(item.id);
        }
      }
    } finally {
      _draining = false;
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    _db?.close();
  }
}
