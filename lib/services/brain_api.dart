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
    final updates = <String, dynamic>{};
    if (entry.category == 'actions') {
      updates['action_done'] = !(entry.actionDone ?? false);
    } else if (entry.category == 'projects') {
      updates['status'] = (entry.status == 'done') ? 'active' : 'done';
    }
    if (updates.isNotEmpty) {
      await updateEntry(entry.id, updates);
    }
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
  });

  /// Whether this entry is "done" (action completed or project status=done).
  bool get isDone {
    if (category == 'actions') return actionDone ?? false;
    if (category == 'projects') return status == 'done';
    return false;
  }

  /// Whether this entry supports done/undone toggling.
  bool get isActionable =>
      category == 'actions' || category == 'projects';

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
    );
  }
}
