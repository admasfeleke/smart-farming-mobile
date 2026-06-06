import 'package:shared_preferences/shared_preferences.dart';

import '../features/disease/disease_history_cache_store.dart';
import '../features/scan/local_scan_history_store.dart';
import '../features/scan/pending_scan_queue_store.dart';
import 'local_db.dart';

class AccountDataResetService {
  AccountDataResetService._();

  static final AccountDataResetService instance = AccountDataResetService._();

  static const Set<String> _exactPreferenceKeys = <String>{
    'alerts_cache_v1',
    'crop_health_history_cache_v1',
    'disease_prevention_crops_cache_v1',
    'home_weather_cache_v1',
    'my_farm_alerts_cache_v1',
    'my_farm_reports_cache_v1',
    'profile_cache_v1',
    'reference_crops_cache_v1',
    'reference_regions_cache_v1',
    'scan_crop_contexts_cache_v1',
    'scan_selected_context_cache_v1',
    'weather_records_cache_v1',
    'weather_summary_cache_v1',
  };

  static const List<String> _preferenceKeyPrefixes = <String>[
    'yield_prediction_cache_v1',
    'my_farm_cache_farms_v1',
    'my_farm_cache_plots_v1_',
    'my_farm_cache_plantings_v1_',
    'disease_prevention_recommendations_cache_v1',
  ];

  Future<void> clearFarmerOwnedData() async {
    await LocalDb.instance.clearFarmerOwnedData();
    await DiseaseHistoryCacheStore.instance.clear();
    await LocalScanHistoryStore.instance.clear();
    await PendingScanQueueStore.instance.clearAll();
    await _clearSharedPreferenceCaches();
  }

  Future<void> _clearSharedPreferenceCaches() async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = prefs.getKeys().where((key) {
      if (_exactPreferenceKeys.contains(key)) return true;
      return _preferenceKeyPrefixes.any((prefix) => key.startsWith(prefix));
    }).toList(growable: false);
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
  }
}
