import 'dart:convert';
import 'package:http/http.dart' as http;

/// REST client for the brain API (status, history).
class BrainApi {
  final String baseUrl;
  final String token;

  BrainApi({required this.baseUrl, required this.token});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Get brain status (agent online, queue counts, etc.)
  Future<BrainStatus> getStatus() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/brain/status'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Status request failed: ${resp.statusCode}');
    }
    return BrainStatus.fromJson(jsonDecode(resp.body));
  }

  /// Get recent thought history.
  Future<List<HistoryEntry>> getHistory({int limit = 20}) async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/brain/history?limit=$limit'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('History request failed: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body);
    final items = data['messages'] as List? ?? [];
    return items.map((e) => HistoryEntry.fromJson(e)).toList();
  }
}

class BrainStatus {
  final bool agentOnline;
  final int queuedCount;
  final String? agentModel;

  BrainStatus({
    required this.agentOnline,
    required this.queuedCount,
    this.agentModel,
  });

  factory BrainStatus.fromJson(Map<String, dynamic> json) {
    return BrainStatus(
      agentOnline: json['agent_online'] ?? false,
      queuedCount: json['queued_count'] ?? 0,
      agentModel: json['model'],
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

  HistoryEntry({
    required this.id,
    required this.text,
    this.category,
    this.title,
    this.confidence,
    required this.timestamp,
    required this.processed,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      id: json['id']?.toString() ?? '',
      text: json['text'] ?? '',
      category: json['category'],
      title: json['title'],
      confidence: json['confidence']?.toDouble(),
      timestamp: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      processed: json['processed'] ?? false,
    );
  }
}
