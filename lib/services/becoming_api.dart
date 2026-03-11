import 'dart:convert';
import 'package:http/http.dart' as http;

/// REST client for ibeco.me practice/memorize endpoints.
///
/// Reuses the same baseUrl + token as BrainApi — the `bec_` token
/// is universal across all ibeco.me endpoints.
class BecomingApi {
  final String baseUrl;
  final String token;

  BecomingApi({required this.baseUrl, required this.token});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Get daily practice summaries for a date (YYYY-MM-DD).
  Future<List<DailySummary>> getDailySummary(String date) async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/daily/$date'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Daily summary failed: ${resp.statusCode}');
    }
    final List<dynamic> data = jsonDecode(resp.body);
    return data.map((e) => DailySummary.fromJson(e)).toList();
  }

  /// Get all active practices.
  Future<List<Practice>> getPractices() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/practices'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Practices failed: ${resp.statusCode}');
    }
    final List<dynamic> data = jsonDecode(resp.body);
    return data.map((e) => Practice.fromJson(e)).toList();
  }

  /// Log a practice set for today (creates a log entry, does NOT retire the practice).
  Future<void> logPractice({
    required int practiceId,
    required String date,
    int? sets,
    int? reps,
    String? value,
  }) async {
    final body = <String, dynamic>{
      'practice_id': practiceId,
      'date': date,
    };
    if (sets != null) body['sets'] = sets;
    if (reps != null) body['reps'] = reps;
    if (value != null) body['value'] = value;

    final resp = await http.post(
      Uri.parse('$baseUrl/api/logs'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (resp.statusCode != 201) {
      throw Exception('Log practice failed: ${resp.statusCode}');
    }
  }

  /// Undo the most recent log for a practice on a given date.
  Future<void> deleteLatestLog({
    required int practiceId,
    required String date,
  }) async {
    final resp = await http.delete(
      Uri.parse('$baseUrl/api/logs/latest?practice_id=$practiceId&date=$date'),
      headers: _headers,
    );
    if (resp.statusCode != 204) {
      throw Exception('Undo log failed: ${resp.statusCode}');
    }
  }

  /// Get memorize cards due for review on a date.
  Future<List<Practice>> getDueCards(String date) async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/memorize/due/$date'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Due cards failed: ${resp.statusCode}');
    }
    final List<dynamic> data = jsonDecode(resp.body);
    return data.map((e) => Practice.fromJson(e)).toList();
  }

  /// Submit a memorize card review.
  Future<Practice> reviewCard({
    required int practiceId,
    required int quality,
    required String date,
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/memorize/review'),
      headers: _headers,
      body: jsonEncode({
        'practice_id': practiceId,
        'quality': quality,
        'date': date,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('Review card failed: ${resp.statusCode}');
    }
    return Practice.fromJson(jsonDecode(resp.body));
  }

  /// Create a new practice.
  Future<Practice> createPractice({
    required String name,
    required String type,
    String category = '',
    String description = '',
    String config = '{}',
    String? startDate,
    String? endDate,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'type': type,
      'category': category,
      'description': description,
      'config': config,
    };
    if (startDate != null) body['start_date'] = startDate;
    if (endDate != null) body['end_date'] = endDate;
    final resp = await http.post(
      Uri.parse('$baseUrl/api/practices'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (resp.statusCode != 201) {
      throw Exception('Create practice failed: ${resp.statusCode}');
    }
    return Practice.fromJson(jsonDecode(resp.body));
  }

  /// Get the next study exercise (smart card selection).
  Future<StudyExercise?> getStudyNext({
    required String date,
    String? lastCardId,
    String? momentum,
    List<double>? recentScores,
  }) async {
    final params = <String, String>{'date': date};
    if (lastCardId != null) params['last_card_id'] = lastCardId;
    if (momentum != null) params['momentum'] = momentum;
    if (recentScores != null && recentScores.isNotEmpty) {
      params['recent_scores'] = recentScores.join(',');
    }
    final uri = Uri.parse('$baseUrl/api/memorize/study/next')
        .replace(queryParameters: params);
    final resp = await http.get(uri, headers: _headers);
    if (resp.statusCode != 200) {
      throw Exception('Study next failed: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['done'] == true) return null;
    return StudyExercise.fromJson(data);
  }
}

// --- Models ---

class Practice {
  final int id;
  final String name;
  final String description;
  final String type;
  final String category;
  final String? sourceDoc;
  final String? sourcePath;
  final String config;
  final int sortOrder;
  final bool active;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final DateTime? archivedAt;
  final String? endDate;
  final String? startDate;
  final int memorizeLevel;

  Practice({
    required this.id,
    required this.name,
    this.description = '',
    required this.type,
    this.category = '',
    this.sourceDoc,
    this.sourcePath,
    this.config = '{}',
    this.sortOrder = 0,
    this.active = true,
    this.status = 'active',
    required this.createdAt,
    this.completedAt,
    this.archivedAt,
    this.endDate,
    this.startDate,
    this.memorizeLevel = 0,
  });

  /// Parse memorize config for SM-2 fields.
  MemorizeConfig? get memorizeConfig {
    if (type != 'memorize') return null;
    try {
      final data = jsonDecode(config) as Map<String, dynamic>;
      return MemorizeConfig.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  factory Practice.fromJson(Map<String, dynamic> json) => Practice(
        id: json['id'] as int,
        name: json['name'] ?? '',
        description: json['description'] ?? '',
        type: json['type'] ?? '',
        category: json['category'] ?? '',
        sourceDoc: json['source_doc'],
        sourcePath: json['source_path'],
        config: json['config'] is String ? json['config'] : jsonEncode(json['config'] ?? {}),
        sortOrder: json['sort_order'] ?? 0,
        active: json['active'] ?? true,
        status: json['status'] ?? 'active',
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        completedAt: json['completed_at'] != null
            ? DateTime.tryParse(json['completed_at'])
            : null,
        archivedAt: json['archived_at'] != null
            ? DateTime.tryParse(json['archived_at'])
            : null,
        endDate: json['end_date'],
        startDate: json['start_date'],
        memorizeLevel: json['memorize_level'] ?? 0,
      );
}

class MemorizeConfig {
  final double easeFactor;
  final int interval;
  final int repetitions;
  final String? nextReview;
  final int targetDailyReps;

  MemorizeConfig({
    this.easeFactor = 2.5,
    this.interval = 0,
    this.repetitions = 0,
    this.nextReview,
    this.targetDailyReps = 1,
  });

  factory MemorizeConfig.fromJson(Map<String, dynamic> json) => MemorizeConfig(
        easeFactor: (json['ease_factor'] ?? 2.5).toDouble(),
        interval: json['interval'] ?? 0,
        repetitions: json['repetitions'] ?? 0,
        nextReview: json['next_review'],
        targetDailyReps: json['target_daily_reps'] ?? 1,
      );
}

class DailySummary {
  final int practiceId;
  final String practiceName;
  final String practiceType;
  final String category;
  final String config;
  final String status;
  final String? endDate;
  final String? startDate;
  final String createdAt;
  final int logCount;
  final int? totalSets;
  final int? totalReps;
  final String? lastValue;
  final String? lastNotes;
  final bool? isDue;
  final String? nextDue;
  final int daysOverdue;
  final List<String> slotsDue;

  DailySummary({
    required this.practiceId,
    required this.practiceName,
    required this.practiceType,
    this.category = '',
    this.config = '{}',
    this.status = 'active',
    this.endDate,
    this.startDate,
    this.createdAt = '',
    this.logCount = 0,
    this.totalSets,
    this.totalReps,
    this.lastValue,
    this.lastNotes,
    this.isDue,
    this.nextDue,
    this.daysOverdue = 0,
    this.slotsDue = const [],
  });

  /// Whether this practice has been completed today (has at least one log).
  bool get isCompletedToday => logCount > 0;

  /// Number of sets completed today (total_sets if available, else log_count).
  int get completedSets => totalSets ?? logCount;

  /// Target number of sets from practice config (default 1).
  int get targetSets {
    try {
      final data = jsonDecode(config) as Map<String, dynamic>;
      return (data['target_sets'] as num?)?.toInt() ?? 1;
    } catch (_) {
      return 1;
    }
  }

  /// Target reps per set from practice config.
  int? get targetReps {
    try {
      final data = jsonDecode(config) as Map<String, dynamic>;
      return (data['target_reps'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// Whether all target sets are completed.
  /// For daily_slots scheduled practices, checks if all slots are done.
  bool get isFullyComplete {
    if (_isDailySlots) return slotsDue.isEmpty;
    return completedSets >= targetSets;
  }

  /// Whether this is a daily_slots scheduled practice.
  bool get _isDailySlots {
    if (practiceType != 'scheduled') return false;
    try {
      final data = jsonDecode(config) as Map<String, dynamic>;
      final sched = data['schedule'] as Map<String, dynamic>?;
      return sched?['type'] == 'daily_slots';
    } catch (_) {
      return false;
    }
  }

  factory DailySummary.fromJson(Map<String, dynamic> json) => DailySummary(
        practiceId: json['practice_id'] as int,
        practiceName: json['practice_name'] ?? '',
        practiceType: json['practice_type'] ?? '',
        category: json['category'] ?? '',
        config: json['config'] is String ? json['config'] : jsonEncode(json['config'] ?? {}),
        status: json['status'] ?? 'active',
        endDate: json['end_date'],
        startDate: json['start_date'],
        createdAt: json['created_at'] ?? '',
        logCount: json['log_count'] ?? 0,
        totalSets: json['total_sets'],
        totalReps: json['total_reps'],
        lastValue: json['last_value'],
        lastNotes: json['last_notes'],
        isDue: json['is_due'],
        nextDue: json['next_due'],
        daysOverdue: json['days_overdue'] ?? 0,
        slotsDue: (json['slots_due'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
}

class StudyExercise {
  final Practice practice;
  final String mode;
  final bool isReverse;
  final int level;
  final String momentum;
  final String cardType;
  final List<String> allCardNames;

  StudyExercise({
    required this.practice,
    required this.mode,
    this.isReverse = false,
    this.level = 0,
    this.momentum = 'steady',
    this.cardType = 'goldilocks',
    this.allCardNames = const [],
  });

  factory StudyExercise.fromJson(Map<String, dynamic> json) => StudyExercise(
        practice: Practice.fromJson(json['practice']),
        mode: json['mode'] ?? '',
        isReverse: json['is_reverse'] ?? false,
        level: json['level'] ?? 0,
        momentum: json['momentum'] ?? 'steady',
        cardType: json['card_type'] ?? 'goldilocks',
        allCardNames: (json['all_card_names'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );
}
