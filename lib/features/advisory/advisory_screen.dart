import 'dart:async';

import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../app_copy.dart';
import '../../connectivity_status_service.dart';
import '../../language_store.dart';
import '../../localization.dart';
import '../../localized_value.dart';
import '../../offline/local_cache_store.dart';
import '../../offline/offline_models.dart';
import '../../offline/offline_repository.dart';
import '../../sync_refresh_notifier.dart';
import '../../widgets/farm_ui.dart';
import '../disease/disease_check_screen.dart';
import '../disease/disease_prevention_screen.dart';
import '../my_farm/yield_prediction_screen.dart';
import '../soil_health/soil_health_screen.dart';
import '../weather/weather_screen.dart';

class AdvisoryScreen extends StatefulWidget {
  const AdvisoryScreen({super.key});

  @override
  State<AdvisoryScreen> createState() => _AdvisoryScreenState();
}

class _AdvisoryScreenState extends State<AdvisoryScreen> {
  static const String _cropCacheKey = 'reference_crops_cache_v1';

  bool _loading = true;
  String? _error;
  FarmRecord? _farm;
  PlotRecord? _plot;
  PlantingRecord? _planting;
  int _soilRecordCount = 0;
  final Map<int, String> _cropNames = <int, String>{};

  @override
  void initState() {
    super.initState();
    syncRefreshNotifier.addListener(_handleSyncRefresh);
    _load();
  }

  @override
  void dispose() {
    syncRefreshNotifier.removeListener(_handleSyncRefresh);
    super.dispose();
  }

  void _handleSyncRefresh() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = OfflineRepository.instance;
      final farms = await repo.listFarms();
      final farm = _selectPreferred<FarmRecord>(farms, (item) => item.isActive);

      PlotRecord? plot;
      PlantingRecord? planting;
      var soilRecordCount = 0;

      if (farm != null) {
        final plots = await repo.listPlotsByFarmLocalId(farm.localId);
        plot = _selectPreferred<PlotRecord>(plots, (item) => item.isActive);
      }

      if (plot != null) {
        final soilRecords = await repo.listSoilHealth(
          plotLocalId: plot.localId,
        );
        soilRecordCount = soilRecords.where((item) => !item.deleted).length;

        final plantings = await repo.listPlantingsByPlotLocalId(plot.localId);
        planting = _selectPreferred<PlantingRecord>(
          plantings,
          (item) => item.isActive,
        );
      }

      await _loadCachedCropNames();

      if (!mounted) return;
      setState(() {
        _farm = farm;
        _plot = plot;
        _planting = planting;
        _soilRecordCount = soilRecordCount;
        _loading = false;
      });
      unawaited(_refreshCropNamesInBackground());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadCachedCropNames() async {
    try {
      final cachedCrops = await LocalCacheStore.instance.readList(
        _cropCacheKey,
      );
      final cachedCropItems = (cachedCrops ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      _cropNames
        ..clear()
        ..addEntries(
          cachedCropItems.map(
            (item) => MapEntry<int, String>(
              item['id'] as int,
              item['name']?.toString().trim().isNotEmpty == true
                  ? LocalizedValue.crop(
                      LanguageStore.notifier.value,
                      item['name']!.toString().trim(),
                    )
                  : AppCopy.cropFallback(
                      LanguageStore.notifier.value,
                      item['id'],
                    ),
            ),
          ),
        );
    } catch (_) {
      _cropNames.clear();
    }
  }

  Future<void> _refreshCropNamesInBackground() async {
    try {
      final crops = await ApiClient.getCrops(page: 1, perPage: 200);
      await LocalCacheStore.instance.write(_cropCacheKey, crops);
      if (!mounted) return;
      setState(() {
        _cropNames
          ..clear()
          ..addEntries(
            crops.map(
              (item) => MapEntry<int, String>(
                item['id'] as int,
                item['name']?.toString().trim().isNotEmpty == true
                    ? LocalizedValue.crop(
                        LanguageStore.notifier.value,
                        item['name']!.toString().trim(),
                      )
                    : AppCopy.cropFallback(
                        LanguageStore.notifier.value,
                        item['id'],
                      ),
              ),
            ),
          );
      });
    } catch (_) {
      // Keep cached crop names and avoid blocking the advisory tab.
    }
  }

  T? _selectPreferred<T>(List<T> items, bool Function(T item) isPreferred) {
    if (items.isEmpty) return null;
    for (final item in items) {
      if (isPreferred(item)) return item;
    }
    return items.first;
  }

  void _openWeather(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const WeatherScreen()));
  }

  void _openSoilHealth(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoilHealthScreen(
          initialFarmId: _farm?.localId,
          initialPlotId: _plot?.localId,
        ),
      ),
    );
  }

  void _openDiseasePrevention(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiseasePreventionScreen(
          initialFarmId: _farm?.localId,
          initialPlotId: _plot?.localId,
          initialCropId: _planting?.cropId,
        ),
      ),
    );
  }

  void _openDiseaseHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DiseaseCheckScreen(showHeader: false),
      ),
    );
  }

  void _openYieldPrediction(BuildContext context) {
    final plot = _plot;
    final planting = _planting;
    if (plot == null || planting == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => YieldPredictionScreen(
          plot: plot,
          planting: planting,
          cropLabel:
              _cropNames[planting.cropId] ??
              AppCopy.cropFallback(
                LanguageStore.notifier.value,
                planting.cropId,
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        return FarmSurface(
          padding: EdgeInsets.zero,
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _AdvisoryHeroCard(
                    languageCode: lang,
                    farmName: _farm?.farmName,
                    plotName: _plot?.plotName,
                    plantingStatus: _planting?.status,
                    soilRecordCount: _soilRecordCount,
                    loading: _loading,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.red.shade800,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ValueListenableBuilder(
                    valueListenable:
                        ConnectivityStatusService.instance.notifier,
                    builder: (context, ApiConnectivityStatus status, _) {
                      if (status.state == ApiConnectivityState.apiOnline) {
                        return const SizedBox.shrink();
                      }
                      final isOffline =
                          status.state == ApiConnectivityState.offline;
                      return Card(
                        color: Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isOffline ? Icons.cloud_off : Icons.wifi_find,
                                color: Colors.orange.shade800,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  isOffline
                                      ? L.t(lang, 'guidance_offline_notice')
                                      : L.t(
                                          lang,
                                          'guidance_api_unreachable_notice',
                                        ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    L.t(lang, 'guidelines'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    L.t(lang, 'guidance_intro'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _AdvisoryActionCard(
                    icon: Icons.wb_sunny_outlined,
                    title: L.t(lang, 'weatherMonitoring'),
                    subtitle: L.t(lang, 'weatherMonitoringSubtitle'),
                    trailing: _farm?.farmName,
                    onTap: () => _openWeather(context),
                  ),
                  const SizedBox(height: 12),
                  _AdvisoryActionCard(
                    icon: Icons.science_outlined,
                    title: L.t(lang, 'soilHealthMonitoring'),
                    subtitle: L.t(lang, 'soilHealthMonitoringSubtitle'),
                    trailing: _soilRecordCount == 0
                        ? L.t(lang, 'advisory_no_soil_records')
                        : L.t(
                            lang,
                            'advisory_soil_records_ready',
                            params: {'count': '$_soilRecordCount'},
                          ),
                    onTap: () => _openSoilHealth(context),
                  ),
                  const SizedBox(height: 12),
                  _AdvisoryActionCard(
                    icon: Icons.shield_outlined,
                    title: L.t(lang, 'disease_prevention'),
                    subtitle: L.t(lang, 'disease_prevention_subtitle'),
                    trailing:
                        _plot?.plotName ??
                        L.t(lang, 'advisory_choose_plot_hint'),
                    onTap: () => _openDiseasePrevention(context),
                  ),
                  const SizedBox(height: 12),
                  _AdvisoryActionCard(
                    icon: Icons.history_rounded,
                    title: L.t(lang, 'scan_history'),
                    subtitle: L.t(lang, 'disease_history_entry_subtitle'),
                    trailing: L.t(lang, 'disease_history_entry_trailing'),
                    onTap: () => _openDiseaseHistory(context),
                  ),
                  const SizedBox(height: 12),
                  _AdvisoryActionCard(
                    icon: Icons.auto_graph_outlined,
                    title: L.t(lang, 'yield_outlook'),
                    subtitle: _planting == null
                        ? L.t(lang, 'advisory_add_planting_for_yield')
                        : L.t(lang, 'advisory_estimate_yield'),
                    trailing: _planting == null
                        ? L.t(lang, 'advisory_no_active_planting_selected')
                        : (_cropNames[_planting!.cropId] ??
                              AppCopy.cropFallback(lang, _planting!.cropId)),
                    enabled: _plot != null && _planting != null,
                    onTap: () => _openYieldPrediction(context),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdvisoryHeroCard extends StatelessWidget {
  final String languageCode;
  final String? farmName;
  final String? plotName;
  final String? plantingStatus;
  final int soilRecordCount;
  final bool loading;

  const _AdvisoryHeroCard({
    required this.languageCode,
    required this.farmName,
    required this.plotName,
    required this.plantingStatus,
    required this.soilRecordCount,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        constraints: const BoxConstraints(minHeight: 230),
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/home/quick_guidelines.jpg'),
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF102408).withValues(alpha: 0.92),
                const Color(0xFF244F12).withValues(alpha: 0.76),
                Colors.black.withValues(alpha: 0.36),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8FFB6).withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.track_changes_outlined,
                        color: Color(0xFF275A12),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L.t(languageCode, 'guidance_center'),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            farmName == null
                                ? L.t(languageCode, 'guidance_add_farm_hint')
                                : L.t(
                                    languageCode,
                                    'guidance_focus_today',
                                    params: {'name': plotName ?? farmName!},
                                  ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFFEAF8D3),
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (loading)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      backgroundColor: Colors.white.withValues(alpha: 0.24),
                      color: const Color(0xFFC6F75C),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _HeroFactChip(
                        icon: Icons.grass,
                        label:
                            farmName ??
                            L.t(languageCode, 'guidance_no_farm_selected'),
                      ),
                      _HeroFactChip(
                        icon: Icons.map_outlined,
                        label:
                            plotName ??
                            L.t(languageCode, 'guidance_no_plot_selected'),
                      ),
                      _HeroFactChip(
                        icon: Icons.eco_outlined,
                        label: plantingStatus == null
                            ? L.t(languageCode, 'dashboard_no_active_planting')
                            : L.t(
                                languageCode,
                                'guidance_status_label',
                                params: {'value': plantingStatus!},
                              ),
                      ),
                      _HeroFactChip(
                        icon: Icons.science_outlined,
                        label: soilRecordCount == 1
                            ? L.t(languageCode, 'guidance_soil_record_one')
                            : L.t(
                                languageCode,
                                'guidance_soil_record_many',
                                params: {'count': '$soilRecordCount'},
                              ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroFactChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroFactChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF3F6E12)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF203214),
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvisoryActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;
  final bool enabled;
  final VoidCallback onTap;

  const _AdvisoryActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: enabled ? 0.12 : 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: enabled ? primary : Colors.grey.shade500,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: enabled ? null : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                    ),
                    if (trailing != null && trailing!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        trailing!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: enabled ? primary : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: enabled ? Colors.grey.shade500 : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
