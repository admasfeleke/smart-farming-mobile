import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalCacheEntry {
  final Object payload;
  final DateTime updatedAt;

  const LocalCacheEntry({
    required this.payload,
    required this.updatedAt,
  });
}

class LocalCacheStore {
  LocalCacheStore._();

  static final LocalCacheStore instance = LocalCacheStore._();

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<void> write(String key, Object payload) async {
    final prefs = await _prefs();
    final envelope = <String, Object?>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    };
    await prefs.setString(key, jsonEncode(envelope));
  }

  Future<LocalCacheEntry?> read(String key) async {
    final prefs = await _prefs();
    final raw = prefs.getString(key)?.trim();
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (!decoded.containsKey('payload')) return null;
      final updatedAt = DateTime.tryParse(decoded['updated_at']?.toString() ?? '');
      return LocalCacheEntry(
        payload: decoded['payload'],
        updatedAt: updatedAt?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> readMap(String key) async {
    final entry = await read(key);
    final payload = entry?.payload;
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) return payload.cast<String, dynamic>();
    return null;
  }

  Future<List<dynamic>?> readList(String key) async {
    final entry = await read(key);
    final payload = entry?.payload;
    return payload is List ? payload : null;
  }

  Future<DateTime?> readUpdatedAt(String key) async {
    final entry = await read(key);
    return entry?.updatedAt;
  }
}
