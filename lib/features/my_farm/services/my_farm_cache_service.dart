import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/farm_model.dart';
import '../models/plot_model.dart';
import '../models/planting_model.dart';

class CachedFarms {
  final List<FarmModel> farms;
  final Map<int, int> plotCounts;

  const CachedFarms({
    required this.farms,
    required this.plotCounts,
  });
}

class MyFarmCacheService {
  static const String _farmsKey = 'my_farm_cache_farms_v1';
  static const String _plotsPrefix = 'my_farm_cache_plots_v1_';
  static const String _plantingsPrefix = 'my_farm_cache_plantings_v1_';

  static Future<void> saveFarms({
    required List<FarmModel> farms,
    required Map<int, int> plotCounts,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'farms': farms.map((e) => e.toJson()).toList(),
      'plot_counts': plotCounts.map((key, value) => MapEntry('$key', value)),
      'saved_at': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_farmsKey, jsonEncode(payload));
  }

  static Future<CachedFarms?> getFarms() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_farmsKey)?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final farmsRaw = decoded['farms'];
      final countsRaw = decoded['plot_counts'];
      if (farmsRaw is! List) return null;

      final farms = farmsRaw
          .whereType<Map<String, dynamic>>()
          .map(FarmModel.fromJson)
          .toList();
      final counts = <int, int>{};
      if (countsRaw is Map) {
        for (final entry in countsRaw.entries) {
          final id = int.tryParse(entry.key.toString());
          final value = entry.value;
          final count = value is int ? value : int.tryParse(value.toString());
          if (id != null && count != null) {
            counts[id] = count;
          }
        }
      }

      return CachedFarms(farms: farms, plotCounts: counts);
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePlots(int farmId, List<PlotModel> plots) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'farm_id': farmId,
      'items': plots.map((e) => e.toJson()).toList(),
      'saved_at': DateTime.now().toIso8601String(),
    };
    await prefs.setString('$_plotsPrefix$farmId', jsonEncode(payload));
  }

  static Future<List<PlotModel>> getPlots(int farmId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_plotsPrefix$farmId')?.trim() ?? '';
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final items = decoded['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(PlotModel.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> savePlantings(int plotId, List<PlantingModel> plantings) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'plot_id': plotId,
      'items': plantings.map((e) => e.toJson()).toList(),
      'saved_at': DateTime.now().toIso8601String(),
    };
    await prefs.setString('$_plantingsPrefix$plotId', jsonEncode(payload));
  }

  static Future<List<PlantingModel>> getPlantings(int plotId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_plantingsPrefix$plotId')?.trim() ?? '';
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final items = decoded['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(PlantingModel.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
