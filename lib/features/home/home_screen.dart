import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../api_client.dart';
import '../../auth_session.dart';
import '../../connectivity_status_service.dart';
import '../../language_store.dart';
import '../../localization.dart';
import '../../offline/local_cache_store.dart';
import '../../offline/offline_models.dart';
import '../../offline/offline_repository.dart';
import '../../sync_refresh_notifier.dart';
import '../../widgets/farm_ui.dart';
import '../advisory/advisory_screen.dart';
import '../disease/disease_check_screen.dart';
import '../disease/disease_prevention_screen.dart';
import '../scan/pending_scan_queue_store.dart';
import '../scan/scan_screen.dart';
import '../soil_health/soil_health_screen.dart';
import '../sync/sync_diagnostics_screen.dart';
import '../weather/weather_screen.dart';

part 'home_weather_strip.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<int>? onRequestTabChange;
  final Future<void> Function()? onRequestRefresh;

  const HomeScreen({
    super.key,
    this.onRequestTabChange,
    this.onRequestRefresh,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_DashboardSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadDashboardSnapshot();
    syncRefreshNotifier.addListener(_handleSyncRefresh);
  }

  @override
  void dispose() {
    syncRefreshNotifier.removeListener(_handleSyncRefresh);
    super.dispose();
  }

  void _handleSyncRefresh() {
    if (!mounted) return;
    setState(() {
      _snapshotFuture = _loadDashboardSnapshot();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final tileWidth = screenWidth > 720 ? (screenWidth - 56) / 3 : (screenWidth - 44) / 2;

    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        return FutureBuilder<_DashboardSnapshot>(
          future: _snapshotFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final loading = snapshot.connectionState == ConnectionState.waiting && data == null;

            return FarmSurface(
              padding: EdgeInsets.zero,
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TodayCard(
                        languageCode: lang,
                        snapshot: data,
                        loading: loading,
                        onPressed: () {
                          final target = _resolvePrimaryTab(data);
                          if (target != null) widget.onRequestTabChange?.call(target);
                        },
                      ),
                      const SizedBox(height: 16),
                      _FarmContextCard(
                        snapshot: data,
                        loading: loading,
                        onOpenFarm: widget.onRequestTabChange == null
                            ? null
                            : () => widget.onRequestTabChange!(1),
                      ),
                      const SizedBox(height: 16),
                      _HomeWeatherStrip(languageCode: lang),
                      const SizedBox(height: 16),
                      _SyncHealthCard(
                        languageCode: lang,
                        snapshot: data,
                        loading: loading,
                        onRefresh: widget.onRequestRefresh,
                        onOpenDiagnostics: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SyncDiagnosticsScreen(
                                onTriggerSync: widget.onRequestRefresh,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _SectionIntro(
                        title: L.t(lang, 'dashboard_quick_actions_title'),
                        subtitle: L.t(lang, 'dashboard_quick_actions_subtitle'),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.08,
                        children: [
                          _ActionCard(
                            title: L.t(lang, 'scan'),
                          subtitle: L.t(lang, 'dashboard_open_scanner_subtitle'),
                          icon: Icons.camera_alt_rounded,
                          color: const Color(0xFFD8F1DC),
                          imageAsset: 'assets/images/home/quick_scan.jpg',
                          onTap: () {
                              if (widget.onRequestTabChange != null) {
                                widget.onRequestTabChange!(2);
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const ScanScreen()),
                                );
                              }
                            },
                          ),
                          _ActionCard(
                            title: L.t(lang, 'my_farm'),
                          subtitle: L.t(lang, 'dashboard_manage_farm_subtitle'),
                          icon: Icons.grass_rounded,
                          color: const Color(0xFFF0E4C6),
                          imageAsset: 'assets/images/home/quick_farm.jpg',
                          onTap: widget.onRequestTabChange == null
                                ? null
                                : () => widget.onRequestTabChange!(1),
                          ),
                          _ActionCard(
                            title: L.t(lang, 'guidelines'),
                          subtitle: L.t(lang, 'dashboard_open_guidance_subtitle'),
                          icon: Icons.track_changes_outlined,
                          color: const Color(0xFFDDEBFA),
                          imageAsset: 'assets/images/home/quick_guidelines.jpg',
                          onTap: () {
                              if (widget.onRequestTabChange != null) {
                                widget.onRequestTabChange!(3);
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const AdvisoryScreen()),
                                );
                              }
                            },
                          ),
                          _ActionCard(
                            title: L.t(lang, 'alerts'),
                          subtitle: L.t(lang, 'dashboard_review_alerts_subtitle'),
                          icon: Icons.warning_amber_rounded,
                          color: const Color(0xFFF9E2D8),
                          imageAsset: 'assets/images/home/quick_alerts.jpg',
                          onTap: widget.onRequestTabChange == null
                                ? null
                                : () => widget.onRequestTabChange!(4),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SectionIntro(
                        title: L.t(lang, 'dashboard_field_guidance_title'),
                        subtitle: L.t(lang, 'dashboard_field_guidance_subtitle'),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _FeatureCard(
                            width: tileWidth,
                            title: L.t(lang, 'weatherMonitoring'),
                            subtitle: L.t(lang, 'dashboard_track_weather_subtitle'),
                            icon: Icons.cloud_outlined,
                            imageAsset: 'assets/images/home/field_weather.jpg',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const WeatherScreen()),
                              );
                            },
                          ),
                          _FeatureCard(
                            width: tileWidth,
                            title: L.t(lang, 'soilHealthMonitoring'),
                            subtitle: L.t(lang, 'dashboard_review_soil_subtitle'),
                            icon: Icons.science_outlined,
                            imageAsset: 'assets/images/home/field_soil.jpg',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SoilHealthScreen(
                                    initialFarmId: data?.primaryFarmLocalId,
                                    initialPlotId: data?.primaryPlotLocalId,
                                  ),
                                ),
                              );
                            },
                          ),
                          _FeatureCard(
                            width: tileWidth,
                            title: L.t(lang, 'disease_prevention'),
                            subtitle: L.t(lang, 'disease_prevention_subtitle'),
                            icon: Icons.shield_outlined,
                            imageAsset: 'assets/images/home/field_prevention.jpg',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DiseasePreventionScreen(
                                    initialFarmId: data?.primaryFarmLocalId,
                                    initialPlotId: data?.primaryPlotLocalId,
                                    initialCropId: data?.primaryCropId,
                                  ),
                                ),
                              );
                            },
                          ),
                          _FeatureCard(
                            width: tileWidth,
                            title: L.t(lang, 'scan_history'),
                            subtitle: L.t(lang, 'disease_history_entry_subtitle'),
                            icon: Icons.history_rounded,
                            imageAsset: 'assets/images/home/field_history.jpg',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const DiseaseCheckScreen(showHeader: false),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  int? _resolvePrimaryTab(_DashboardSnapshot? snapshot) {
    if (snapshot == null || snapshot.farmCount == 0) return 1;
    if (snapshot.pendingScans > 0) return 2;
    return 3;
  }
}

class _DashboardSnapshot {
  final String? userName;
  final int farmCount;
  final int plotCount;
  final int activePlantingCount;
  final int soilRecordCount;
  final int pendingScans;
  final int pendingSyncItems;
  final int failedSyncItems;
  final int conflictSyncItems;
  final int deleteSyncItems;
  final bool offlineModeActive;
  final bool hasServerToken;
  final int? primaryFarmLocalId;
  final int? primaryPlotLocalId;
  final int? primaryCropId;
  final String? primaryFarmName;
  final String? primaryPlotName;
  final String? primaryPlantingStatus;

  const _DashboardSnapshot({
    required this.userName,
    required this.farmCount,
    required this.plotCount,
    required this.activePlantingCount,
    required this.soilRecordCount,
    required this.pendingScans,
    required this.pendingSyncItems,
    required this.failedSyncItems,
    required this.conflictSyncItems,
    required this.deleteSyncItems,
    required this.offlineModeActive,
    required this.hasServerToken,
    required this.primaryFarmLocalId,
    required this.primaryPlotLocalId,
    required this.primaryCropId,
    required this.primaryFarmName,
    required this.primaryPlotName,
    required this.primaryPlantingStatus,
  });
}

Future<_DashboardSnapshot> _loadDashboardSnapshot() async {
  final userName = await AuthSession.getUserName();
  final offlineModeActive = await AuthSession.isOfflineModeActive();
  final hasServerToken = await ApiClient.hasServerSessionCapability();
  final repo = OfflineRepository.instance;
  final farms = await repo.listFarms();
  final primaryFarm = _pickPreferred<FarmRecord>(farms, (item) => item.isActive);

  var plotCount = 0;
  var activePlantingCount = 0;
  var soilRecordCount = 0;
  PlotRecord? primaryPlot;
  PlantingRecord? primaryPlanting;

  for (final farm in farms) {
    final plots = await repo.listPlotsByFarmLocalId(farm.localId);
    plotCount += plots.length;

    if (primaryFarm != null && farm.localId == primaryFarm.localId) {
      primaryPlot = _pickPreferred<PlotRecord>(plots, (item) => item.isActive);
    }

    for (final plot in plots) {
      final plantings = await repo.listPlantingsByPlotLocalId(plot.localId);
      activePlantingCount += plantings.where((item) => item.isActive && !item.deleted).length;
      final soilRecords = await repo.listSoilHealth(plotLocalId: plot.localId);
      soilRecordCount += soilRecords.where((item) => !item.deleted).length;
    }
  }

  if (primaryPlot != null) {
    final plantings = await repo.listPlantingsByPlotLocalId(primaryPlot.localId);
    primaryPlanting = _pickPreferred<PlantingRecord>(plantings, (item) => item.isActive);
  }

  var pendingScans = 0;
  try {
    pendingScans = (await PendingScanQueueStore.instance.listAll()).length;
  } catch (_) {
    pendingScans = 0;
  }
  final syncSummary = await repo.getSyncSummary();

  return _DashboardSnapshot(
    userName: userName,
    farmCount: farms.length,
    plotCount: plotCount,
    activePlantingCount: activePlantingCount,
    soilRecordCount: soilRecordCount,
    pendingScans: pendingScans,
    pendingSyncItems: syncSummary.actionableCount,
    failedSyncItems: syncSummary.failedCount,
    conflictSyncItems: syncSummary.conflictCount,
    deleteSyncItems: syncSummary.deletedCount,
    offlineModeActive: offlineModeActive,
    hasServerToken: hasServerToken,
    primaryFarmLocalId: primaryFarm?.localId,
    primaryPlotLocalId: primaryPlot?.localId,
    primaryCropId: primaryPlanting?.cropId,
    primaryFarmName: primaryFarm?.farmName,
    primaryPlotName: primaryPlot?.plotName,
    primaryPlantingStatus: primaryPlanting?.status,
  );
}

T? _pickPreferred<T>(List<T> items, bool Function(T item) isPreferred) {
  if (items.isEmpty) return null;
  for (final item in items) {
    if (isPreferred(item)) return item;
  }
  return items.first;
}

class _TodayCard extends StatelessWidget {
  final String languageCode;
  final _DashboardSnapshot? snapshot;
  final bool loading;
  final VoidCallback onPressed;

  const _TodayCard({
    required this.languageCode,
    required this.snapshot,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = snapshot;
    final name = (data?.userName ?? '').trim();
    final greeting = name.isNotEmpty
        ? L.t(languageCode, 'welcome', params: {'name': name})
        : 'Smart Farming';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF385B13).withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/crops/maize.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: theme.colorScheme.primary),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.68),
                    const Color(0xFF355B12).withValues(alpha: 0.72),
                    const Color(0xFFF2D35B).withValues(alpha: 0.30),
                  ],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  child: Text(
                    'Smart field dashboard',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  greeting,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  L.t(languageCode, 'dashboard_today_title'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (loading)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: const LinearProgressIndicator(minHeight: 4),
                  )
                else
                  Text(
                    _message(data),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      height: 1.35,
                    ),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryChip(label: '${L.t(languageCode, 'my_farm')}: ${data?.farmCount ?? 0}', icon: Icons.grass),
                    _SummaryChip(label: '${L.t(languageCode, 'plots')}: ${data?.plotCount ?? 0}', icon: Icons.map_outlined),
                    _SummaryChip(
                      label: '${L.t(languageCode, 'dashboard_plantings_label')}: ${data?.activePlantingCount ?? 0}',
                      icon: Icons.eco_outlined,
                    ),
                    _SummaryChip(
                      label: '${L.t(languageCode, 'dashboard_queued_scans_label')}: ${data?.pendingScans ?? 0}',
                      icon: Icons.cloud_upload_outlined,
                      backgroundColor: (data?.pendingScans ?? 0) > 0
                          ? const Color(0xFFFFE1A6)
                          : Colors.white.withValues(alpha: 0.86),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(_buttonLabel(data)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFCFF36A),
                    foregroundColor: const Color(0xFF15210B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _message(_DashboardSnapshot? data) {
    if (data == null) return L.t(languageCode, 'dashboard_loading_context');
    if (data.farmCount == 0) return L.t(languageCode, 'dashboard_add_first_farm');
    if (data.conflictSyncItems > 0) {
      return L.t(languageCode, 'dashboard_attention_conflict');
    }
      if (data.offlineModeActive && !data.hasServerToken) {
        return L.t(languageCode, 'dashboard_attention_online_sign_in_required');
      }
      if (data.offlineModeActive) {
        return L.t(languageCode, 'dashboard_attention_offline_mode');
      }
    if (data.pendingScans > 0 || data.pendingSyncItems > 0) {
      return L.t(languageCode, 'dashboard_sync_scans_attention');
    }
    if (data.activePlantingCount == 0) return L.t(languageCode, 'dashboard_add_active_planting');
    return L.t(languageCode, 'dashboard_ready_attention');
  }

  String _buttonLabel(_DashboardSnapshot? data) {
    if (data == null || data.farmCount == 0) return L.t(languageCode, 'dashboard_open_my_farm');
    if (data.pendingScans > 0) return L.t(languageCode, 'dashboard_open_scan');
    return L.t(languageCode, 'dashboard_open_advisory');
  }
}

class _FarmContextCard extends StatelessWidget {
  final _DashboardSnapshot? snapshot;
  final bool loading;
  final VoidCallback? onOpenFarm;

  const _FarmContextCard({
    required this.snapshot,
    required this.loading,
    required this.onOpenFarm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = snapshot;

    return FarmPanel(
      color: const Color(0xFFFFFCF0),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F2B9),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: const Icon(Icons.agriculture_rounded, color: Color(0xFF41670F)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L.t(LanguageStore.notifier.value, 'dashboard_current_field_context'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF1E2A12),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _fieldContextSummary(data),
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                if (onOpenFarm != null)
                  TextButton.icon(
                    onPressed: onOpenFarm,
                    icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                    label: Text(L.t(LanguageStore.notifier.value, 'my_farm')),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (loading)
              const LinearProgressIndicator(minHeight: 3)
            else if (data == null || data.farmCount == 0)
              _EmptyContextPanel(
                text: L.t(LanguageStore.notifier.value, 'no_farms'),
                onTap: onOpenFarm,
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ContextTile(
                    label: L.t(LanguageStore.notifier.value, 'dashboard_farm_site'),
                    value: data.primaryFarmName ?? L.t(LanguageStore.notifier.value, 'dashboard_not_selected'),
                    icon: Icons.grass_rounded,
                    color: const Color(0xFFDFF0B4),
                  ),
                  _ContextTile(
                    label: L.t(LanguageStore.notifier.value, 'dashboard_priority_plot'),
                    value: data.primaryPlotName ?? L.t(LanguageStore.notifier.value, 'dashboard_not_selected'),
                    icon: Icons.map_outlined,
                    color: const Color(0xFFDDEBFA),
                  ),
                  _ContextTile(
                    label: L.t(LanguageStore.notifier.value, 'dashboard_planting_status'),
                    value: data.primaryPlantingStatus ??
                        L.t(LanguageStore.notifier.value, 'dashboard_no_active_planting'),
                    icon: Icons.eco_outlined,
                    color: const Color(0xFFE7E1CC),
                  ),
                  _ContextTile(
                    label: L.t(LanguageStore.notifier.value, 'dashboard_soil_records'),
                    value: data.soilRecordCount == 1
                        ? L.t(LanguageStore.notifier.value, 'dashboard_records_available_one')
                        : L.t(
                            LanguageStore.notifier.value,
                            'dashboard_records_available_many',
                            params: {'count': '${data.soilRecordCount}'},
                          ),
                    icon: Icons.science_outlined,
                    color: const Color(0xFFF1E2B5),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _fieldContextSummary(_DashboardSnapshot? data) {
    final lang = LanguageStore.notifier.value;
    if (data == null || data.farmCount == 0) {
      return L.t(lang, 'dashboard_add_first_farm');
    }
    return '${data.farmCount} ${L.t(lang, 'my_farm')} | ${data.plotCount} ${L.t(lang, 'plots')}';
  }
}

class _SyncHealthCard extends StatelessWidget {
  final String languageCode;
  final _DashboardSnapshot? snapshot;
  final bool loading;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onOpenDiagnostics;

  const _SyncHealthCard({
    required this.languageCode,
    required this.snapshot,
    required this.loading,
    required this.onRefresh,
    required this.onOpenDiagnostics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = snapshot;

    return ValueListenableBuilder(
      valueListenable: ConnectivityStatusService.instance.notifier,
      builder: (context, ApiConnectivityStatus status, _) {
        final headline = _headline(status, data);
        final detail = _detail(status, data);
        final tone = _toneColor(status, data, theme);
        final icon = _icon(status, data);

        return FarmPanel(
          color: Color.lerp(const Color(0xFFFFFDF5), tone, 0.08),
          child: Padding(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: tone),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L.t(languageCode, 'sync_health_title'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            headline,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onRefresh != null)
                      IconButton.filledTonal(
                        onPressed: () {
                          unawaited(onRefresh!.call());
                        },
                        icon: const Icon(Icons.sync),
                        tooltip: L.t(languageCode, 'sync_action_sync'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (loading)
                  const LinearProgressIndicator(minHeight: 3)
                else ...[
                  Text(
                    detail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SummaryChip(
                        label: '${L.t(languageCode, 'dashboard_sync_backlog_label')}: ${data?.pendingSyncItems ?? 0}',
                        icon: Icons.sync_problem_outlined,
                        backgroundColor: Colors.amber.shade50,
                      ),
                      _SummaryChip(
                        label: L.t(
                          languageCode,
                          'sync_status_failed',
                          params: {'count': '${data?.failedSyncItems ?? 0}'},
                        ),
                        icon: Icons.error_outline,
                        backgroundColor: Colors.red.shade50,
                      ),
                      _SummaryChip(
                        label: L.t(
                          languageCode,
                          'sync_status_conflicts',
                          params: {'count': '${data?.conflictSyncItems ?? 0}'},
                        ),
                        icon: Icons.rule_folder_outlined,
                        backgroundColor: Colors.deepOrange.shade50,
                      ),
                      _SummaryChip(
                        label: L.t(
                          languageCode,
                          'sync_status_queued_scans',
                          params: {'count': '${data?.pendingScans ?? 0}'},
                        ),
                        icon: Icons.cloud_upload_outlined,
                        backgroundColor: Colors.orange.shade50,
                      ),
                    ],
                  ),
                  if (onOpenDiagnostics != null) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onOpenDiagnostics,
                        icon: const Icon(Icons.insights_outlined),
                        label: Text(L.t(languageCode, 'sync_action_view_diagnostics')),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _headline(ApiConnectivityStatus status, _DashboardSnapshot? data) {
    if ((data?.offlineModeActive ?? false) && !(data?.hasServerToken ?? false)) {
      return L.t(languageCode, 'sync_headline_online_sign_in_required');
    }
    if (data?.offlineModeActive ?? false) return L.t(languageCode, 'sync_headline_offline_mode_active');
    if ((data?.conflictSyncItems ?? 0) > 0) return L.t(languageCode, 'sync_headline_needs_review');
    if ((data?.failedSyncItems ?? 0) > 0) return L.t(languageCode, 'sync_headline_retry_pending');
    switch (status.state) {
      case ApiConnectivityState.apiOnline:
        return L.t(languageCode, 'sync_headline_server_reachable');
      case ApiConnectivityState.internetOnly:
        return L.t(languageCode, 'sync_headline_internet_only');
      case ApiConnectivityState.offline:
        return L.t(languageCode, 'sync_headline_offline');
    }
  }

  String _detail(ApiConnectivityStatus status, _DashboardSnapshot? data) {
    if (data == null) return L.t(languageCode, 'sync_detail_loading_local_summary');
    if (data.offlineModeActive && !data.hasServerToken) {
      return L.t(languageCode, 'sync_detail_online_sign_in_required');
    }
    if (data.offlineModeActive) {
      return L.t(languageCode, 'sync_detail_offline_mode');
    }
    if (data.conflictSyncItems > 0) {
      return L.t(languageCode, 'sync_detail_conflict_review');
    }
    if (data.failedSyncItems > 0) {
      return L.t(languageCode, 'sync_detail_failed_retry');
    }
    if (data.pendingSyncItems > 0 || data.pendingScans > 0) {
      if (status.state == ApiConnectivityState.apiOnline) {
        return L.t(languageCode, 'sync_detail_pending_online');
      }
      return L.t(languageCode, 'sync_detail_pending_offline');
    }
    if (status.state == ApiConnectivityState.apiOnline) {
      return L.t(languageCode, 'sync_detail_ready_online');
    }
    return L.t(languageCode, 'sync_detail_limited_connectivity');
  }

  Color _toneColor(
    ApiConnectivityStatus status,
    _DashboardSnapshot? data,
    ThemeData theme,
  ) {
    if ((data?.conflictSyncItems ?? 0) > 0) return Colors.deepOrange.shade700;
    if ((data?.failedSyncItems ?? 0) > 0) return Colors.red.shade700;
    if ((data?.offlineModeActive ?? false) || status.state != ApiConnectivityState.apiOnline) {
      return Colors.orange.shade700;
    }
    return theme.colorScheme.primary;
  }

  IconData _icon(ApiConnectivityStatus status, _DashboardSnapshot? data) {
    if ((data?.conflictSyncItems ?? 0) > 0) return Icons.rule_folder_outlined;
    if ((data?.failedSyncItems ?? 0) > 0) return Icons.error_outline;
    if ((data?.offlineModeActive ?? false) || status.state == ApiConnectivityState.offline) {
      return Icons.cloud_off;
    }
    if (status.state == ApiConnectivityState.internetOnly) {
      return Icons.wifi_find;
    }
    return Icons.cloud_done;
  }
}

class _SectionIntro extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionIntro({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: const Color(0xFF1E2A12),
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700)),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String imageAsset;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.imageAsset,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  imageAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(color: color),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.72),
                        const Color(0xFF23410E).withValues(alpha: 0.48),
                        Colors.white.withValues(alpha: 0.04),
                      ],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(icon, size: 25, color: theme.colorScheme.primary),
                      ),
                      const Spacer(),
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.86),
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final double width;
  final String title;
  final String subtitle;
  final IconData icon;
  final String imageAsset;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.width,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.imageAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF5),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4D5B25).withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      imageAsset,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFFFFDF5)),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.72),
                            const Color(0xFF315815).withValues(alpha: 0.42),
                            Colors.transparent,
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topRight,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDDEF9D).withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(icon, color: const Color(0xFF24420C)),
                        ),
                        const SizedBox(height: 34),
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w700,
                            height: 1.24,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyContextPanel extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;

  const _EmptyContextPanel({required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5D7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5C56B).withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.add_location_alt_outlined, color: Color(0xFF8A6500)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF57430A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onTap != null)
            IconButton(
              onPressed: onTap,
              icon: const Icon(Icons.arrow_forward_rounded),
              color: const Color(0xFF8A6500),
            ),
        ],
      ),
    );
  }
}

class _ContextTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ContextTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final width = screenWidth >= 720 ? (screenWidth - 42) / 2 : screenWidth - 32;
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 20, color: const Color(0xFF41670F)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.black.withValues(alpha: 0.56),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF1E2A12),
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? backgroundColor;

  const _SummaryChip({required this.label, required this.icon, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
