import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/disease_report_model.dart';

class DiseaseHistoryCacheStore {
  DiseaseHistoryCacheStore._();

  static final DiseaseHistoryCacheStore instance = DiseaseHistoryCacheStore._();

  static const String _itemsKey = 'disease_history_server_cache_v3_items';
  static const String _savedAtKey = 'disease_history_server_cache_v3_saved_at';

  Future<List<DiseaseReportModel>> listAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_itemsKey) ?? const <String>[];
    final items = <DiseaseReportModel>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          items.add(DiseaseReportModel.fromJson(decoded));
        }
      } catch (_) {
        continue;
      }
    }
    return items;
  }

  Future<void> saveAll(List<DiseaseReportModel> reports) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = reports
        .map((report) => jsonEncode(report.toJson()))
        .toList(growable: false);
    await prefs.setStringList(_itemsKey, raw);
    await prefs.setInt(_savedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<DateTime?> savedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_savedAtKey);
    if (value == null || value <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_itemsKey);
    await prefs.remove(_savedAtKey);
  }
}
