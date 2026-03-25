import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'brain_api.dart';

/// Local cache for brain entries using SharedPreferences.
/// Stores the last successful getHistory() result so the app
/// can display entries even when the server is unreachable.
class EntryCache {
  static const _entriesKey = 'cached_entries';
  static const _timestampKey = 'cached_entries_at';

  /// Save entries to local cache.
  Future<void> cacheEntries(List<HistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final json = entries.map((e) => e.toJson()).toList();
    await prefs.setString(_entriesKey, jsonEncode(json));
    await prefs.setString(_timestampKey, DateTime.now().toIso8601String());
  }

  /// Load cached entries. Returns null if no cache exists.
  Future<CachedResult?> getCachedEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_entriesKey);
    if (raw == null) return null;

    final tsRaw = prefs.getString(_timestampKey);
    final cachedAt = tsRaw != null ? DateTime.tryParse(tsRaw) : null;

    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return CachedResult(entries: list, cachedAt: cachedAt);
    } catch (_) {
      return null;
    }
  }

  /// Clear the cache.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_entriesKey);
    await prefs.remove(_timestampKey);
  }
}

/// Result from the entry cache, with a timestamp of when data was cached.
class CachedResult {
  final List<HistoryEntry> entries;
  final DateTime? cachedAt;

  CachedResult({required this.entries, this.cachedAt});
}
