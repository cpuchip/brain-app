import 'dart:convert';
import 'package:http/http.dart' as http;

/// REST client for the brain API (status, entries, CRUD).
///
/// Supports two modes:
/// - **Relay mode** (baseUrl = ibeco.me): entries from synced cache, CRUD proxied through relay
/// - **Direct mode** (brainUrl = brain.exe LAN): real SQLite data + local CRUD
class BrainApi {
  final String baseUrl;
  final String token;

  /// Optional direct URL to brain.exe for LAN access.
  /// When set, status/entries/CRUD go here instead of [baseUrl].
  final String? brainUrl;

  BrainApi({required this.baseUrl, required this.token, this.brainUrl});

  /// Whether a direct brain.exe connection is configured.
  bool get hasBrainUrl => brainUrl != null && brainUrl!.isNotEmpty;

  /// The URL to use for data reads (brain.exe if available, otherwise relay).
  String get _dataUrl => hasBrainUrl ? brainUrl! : baseUrl;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Get brain status (agent online, queue counts, etc.)
  Future<BrainStatus> getStatus() async {
    final resp = await http.get(
      Uri.parse('$_dataUrl/api/brain/status'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Status request failed: ${resp.statusCode}');
    }
    return BrainStatus.fromJson(jsonDecode(resp.body));
  }

  /// Get brain entries. Uses /api/brain/entries (synced cache) on relay,
  /// or /api/brain/history on direct brain.exe.
  Future<List<HistoryEntry>> getHistory({int limit = 50}) async {
    if (hasBrainUrl) {
      // Direct mode: use brain.exe history endpoint
      final resp = await http.get(
        Uri.parse('$brainUrl/api/brain/history?limit=$limit'),
        headers: _headers,
      );
      if (resp.statusCode != 200) {
        throw Exception('History request failed: ${resp.statusCode}');
      }
      final data = jsonDecode(resp.body);
      final items = data['messages'] as List? ?? [];
      return items.map((e) => HistoryEntry.fromJson(e)).toList();
    }

    // Relay mode: use synced brain_entries cache
    final resp = await http.get(
      Uri.parse('$baseUrl/api/brain/entries'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Entries request failed: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body);
    final items = data['entries'] as List? ?? [];
    return items.map((e) => HistoryEntry.fromBrainEntry(e)).toList();
  }

  /// Update an entry. Works via relay (ibeco.me) or direct (brain.exe).
  Future<void> updateEntry(String id, Map<String, dynamic> updates) async {
    if (hasBrainUrl) {
      final resp = await http.put(
        Uri.parse('$brainUrl/api/entries/${Uri.encodeComponent(id)}'),
        headers: _headers,
        body: jsonEncode(updates),
      );
      if (resp.statusCode != 200) {
        throw Exception('Update failed: ${resp.statusCode}');
      }
    } else {
      final resp = await http.put(
        Uri.parse('$baseUrl/api/brain/entries?id=${Uri.encodeComponent(id)}'),
        headers: _headers,
        body: jsonEncode(updates),
      );
      if (resp.statusCode != 200) {
        throw Exception('Update failed: ${resp.statusCode}');
      }
    }
  }

  /// Toggle done state for an entry.
  Future<void> toggleDone(HistoryEntry entry) async {
    await updateEntry(entry.id, {'action_done': !entry.isDone});
  }

  /// Delete an entry. Works via relay (ibeco.me) or direct (brain.exe).
  Future<void> deleteEntry(String id) async {
    if (hasBrainUrl) {
      final resp = await http.delete(
        Uri.parse('$brainUrl/api/entries/${Uri.encodeComponent(id)}'),
        headers: _headers,
      );
      if (resp.statusCode != 204 && resp.statusCode != 200) {
        throw Exception('Delete failed: ${resp.statusCode}');
      }
    } else {
      final resp = await http.delete(
        Uri.parse('$baseUrl/api/brain/entries?id=${Uri.encodeComponent(id)}'),
        headers: _headers,
      );
      if (resp.statusCode != 200 && resp.statusCode != 204) {
        throw Exception('Delete failed: ${resp.statusCode}');
      }
    }
  }

  /// Create a new brain entry. Returns the created entry.
  Future<HistoryEntry> createEntry({
    required String title,
    required String body,
    String category = 'inbox',
    String? status,
    String? dueDate,
    String? nextAction,
    List<String>? tags,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'body': body,
      'category': category,
      'source': 'app',
    };
    if (status != null && status.isNotEmpty) payload['status'] = status;
    if (dueDate != null && dueDate.isNotEmpty) payload['due_date'] = dueDate;
    if (nextAction != null && nextAction.isNotEmpty) payload['next_action'] = nextAction;
    if (tags != null && tags.isNotEmpty) payload['tags'] = tags;

    if (hasBrainUrl) {
      final resp = await http.post(
        Uri.parse('$brainUrl/api/entries'),
        headers: _headers,
        body: jsonEncode(payload),
      );
      if (resp.statusCode != 201 && resp.statusCode != 200) {
        throw Exception('Create failed: ${resp.statusCode}');
      }
      return HistoryEntry.fromJson(jsonDecode(resp.body));
    } else {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/brain/entries'),
        headers: _headers,
        body: jsonEncode(payload),
      );
      if (resp.statusCode != 201 && resp.statusCode != 200) {
        throw Exception('Create failed: ${resp.statusCode}');
      }
      return HistoryEntry.fromBrainEntry(jsonDecode(resp.body));
    }
  }

  /// Archive an entry by setting its status to "archived".
  Future<void> archiveEntry(String id) async {
    await updateEntry(id, {'status': 'archived'});
  }

  /// Trigger AI classification on an existing entry.
  /// - **Direct mode**: returns the updated entry immediately.
  /// - **Relay mode**: queues the request; returns null (result arrives async via entry_updated).
  Future<HistoryEntry?> classifyEntry(String id) async {
    if (hasBrainUrl) {
      // Direct: synchronous classify + response
      final resp = await http.post(
        Uri.parse('$brainUrl/api/entries/${Uri.encodeComponent(id)}/classify'),
        headers: _headers,
      );
      if (resp.statusCode != 200) {
        throw Exception('Classify failed: ${resp.statusCode}');
      }
      return HistoryEntry.fromJson(jsonDecode(resp.body));
    }
    // Relay: queue classify request through ibeco.me
    final resp = await http.post(
      Uri.parse('$baseUrl/api/brain/entries/classify?id=${Uri.encodeComponent(id)}'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Classify failed: ${resp.statusCode}');
    }
    return null; // result arrives async via entry_updated
  }
}

class BrainStatus {
  final bool agentOnline;
  final int queuedCount;
  final String? agentModel;
  final int? totalEntries;

  BrainStatus({
    required this.agentOnline,
    required this.queuedCount,
    this.agentModel,
    this.totalEntries,
  });

  factory BrainStatus.fromJson(Map<String, dynamic> json) {
    return BrainStatus(
      agentOnline: json['agent_online'] ?? false,
      queuedCount: json['queued_count'] ?? 0,
      agentModel: json['model'],
      totalEntries: json['total_entries'],
    );
  }
}

class HistoryEntry {
  final String id;
  final String text;
  final String? category;
  final String? title;
  final double? confidence;
  final DateTime timestamp;
  final bool processed;
  final bool? actionDone;
  final String? status;
  final String? dueDate;
  final String? nextAction;
  final List<String> tags;

  HistoryEntry({
    required this.id,
    required this.text,
    this.category,
    this.title,
    this.confidence,
    required this.timestamp,
    required this.processed,
    this.actionDone,
    this.status,
    this.dueDate,
    this.nextAction,
    this.tags = const [],
  });

  /// Whether this entry is marked done.
  bool get isDone => actionDone ?? false;

  /// All entries support done/undone toggling.
  bool get isActionable => true;

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      id: json['id']?.toString() ?? '',
      text: json['text'] ?? '',
      category: json['category'],
      title: json['title'],
      confidence: json['confidence']?.toDouble(),
      timestamp: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      processed: json['processed'] ?? false,
      actionDone: json['action_done'],
      status: json['status'],
      dueDate: json['due_date'],
      nextAction: json['next_action'],
      tags: _parseTags(json['tags']),
    );
  }

  /// Parse from the /api/brain/entries BrainEntry format.
  factory HistoryEntry.fromBrainEntry(Map<String, dynamic> json) {
    return HistoryEntry(
      id: json['id']?.toString() ?? '',
      text: json['body'] ?? '',
      category: json['category'],
      title: json['title'],
      confidence: null,
      timestamp: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      processed: true,
      actionDone: json['action_done'],
      status: json['status'],
      dueDate: json['due_date'],
      nextAction: json['next_action'],
      tags: _parseTags(json['tags']),
    );
  }

  static List<String> _parseTags(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String && v.isNotEmpty) return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return [];
  }
}
