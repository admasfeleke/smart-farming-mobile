import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class LocalScanHistoryEntry {
  final String submissionId;
  final int plotId;
  final int cropId;
  final int? plantingId;
  final String imagePath;
  final DateTime capturedAtUtc;
  final DateTime syncedAtUtc;
  final Map<String, dynamic>? scanMetadata;

  const LocalScanHistoryEntry({
    required this.submissionId,
    required this.plotId,
    required this.cropId,
    required this.plantingId,
    required this.imagePath,
    required this.capturedAtUtc,
    required this.syncedAtUtc,
    required this.scanMetadata,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'submission_id': submissionId,
        'plot_id': plotId,
        'crop_id': cropId,
        'planting_id': plantingId,
        'image_path': imagePath,
        'captured_at_utc': capturedAtUtc.toIso8601String(),
        'synced_at_utc': syncedAtUtc.toIso8601String(),
        'scan_metadata': scanMetadata,
      };

  factory LocalScanHistoryEntry.fromJson(Map<String, dynamic> json) {
    return LocalScanHistoryEntry(
      submissionId: json['submission_id']?.toString() ?? '',
      plotId: json['plot_id'] is num ? (json['plot_id'] as num).toInt() : 0,
      cropId: json['crop_id'] is num ? (json['crop_id'] as num).toInt() : 0,
      plantingId: json['planting_id'] is num
          ? (json['planting_id'] as num).toInt()
          : null,
      imagePath: json['image_path']?.toString() ?? '',
      capturedAtUtc:
          DateTime.tryParse(json['captured_at_utc']?.toString() ?? '')
                  ?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      syncedAtUtc:
          DateTime.tryParse(json['synced_at_utc']?.toString() ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      scanMetadata: json['scan_metadata'] is Map
          ? (json['scan_metadata'] as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : null,
    );
  }

  bool get hasMeaningfulOfflineResult {
    final raw = scanMetadata?['offline_local_disease_name']?.toString().trim();
    return raw != null && raw.isNotEmpty;
  }

  bool get imageExists {
    if (imagePath.trim().isEmpty) return false;
    return File(imagePath).existsSync();
  }
}

class LocalScanHistoryStore {
  LocalScanHistoryStore._();

  static final LocalScanHistoryStore instance = LocalScanHistoryStore._();

  static const String _prefsKey = 'synced_local_scan_history_v1';

  Future<List<LocalScanHistoryEntry>> listAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const <String>[];
    final entries = <LocalScanHistoryEntry>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          final entry = LocalScanHistoryEntry.fromJson(decoded);
          if (entry.submissionId.isNotEmpty) {
            entries.add(entry);
          }
        }
      } catch (_) {
        continue;
      }
    }
    entries.sort((a, b) => a.capturedAtUtc.compareTo(b.capturedAtUtc));
    return entries;
  }

  Future<void> upsert(LocalScanHistoryEntry entry) async {
    final all = await listAll();
    final next = all
        .where((item) => item.submissionId != entry.submissionId)
        .toList(growable: true)
      ..add(entry);
    await _write(next);
  }

  Future<void> deleteBySubmissionId(String submissionId) async {
    final all = await listAll();
    final next = all
        .where((item) => item.submissionId != submissionId)
        .toList(growable: false);
    await _write(next);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  Future<void> pruneInvalidEntries() async {
    final all = await listAll();
    final next = all
        .where(
          (entry) =>
              entry.submissionId.isNotEmpty &&
              entry.hasMeaningfulOfflineResult &&
              entry.imageExists,
        )
        .toList(growable: false);
    if (next.length != all.length) {
      await _write(next);
    }
  }

  Future<void> _write(List<LocalScanHistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = entries
        .map((entry) => jsonEncode(entry.toJson()))
        .toList(growable: false);
    await prefs.setStringList(_prefsKey, raw);
  }
}
