import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'providers/farm_context_provider.dart';
import 'widgets/farm_list_widget.dart';
import 'widgets/plot_list_widget.dart';
import 'widgets/planting_list_widget.dart';
import 'yield_prediction_screen.dart';
import '../scan/scan_screen.dart';
import '../../offline/offline_models.dart';
import '../../offline/offline_repository.dart';
import '../../offline/offline_sync_service.dart';
import '../../offline/local_cache_store.dart';
import '../../api_client.dart';
import '../../models/alert_model.dart';
import '../../models/disease_report_model.dart';
import '../my_farm/alerts_mock.dart';
import '../../widgets/error_banner.dart';
import '../../language_store.dart';
import '../../localization.dart';
import '../../localized_value.dart';
import '../../crop_scope.dart';
import '../../sync_refresh_notifier.dart';
import '../../reference/reference_data.dart';
import '../../widgets/farm_ui.dart';

class MyFarmScreen extends StatefulWidget {
  const MyFarmScreen({super.key});

  @override
  State<MyFarmScreen> createState() => _MyFarmScreenState();
}

class _MyFarmScreenState extends State<MyFarmScreen> {
  static const String _alertsCacheKey = 'my_farm_alerts_cache_v1';
  static const String _reportsCacheKey = 'my_farm_reports_cache_v1';
  static const String _cropsCacheKey = 'reference_crops_cache_v1';
  static const String _regionsCacheKey = 'reference_regions_cache_v1';

  bool _isRedirecting = false;
  bool _farmsLoading = false;
  String? _farmsError;
  String? _lastShownFarmsError;
  final List<FarmRecord> _farms = [];
  final Map<int, int> _plotCounts = {};

  bool _plotsLoading = false;
  String? _plotsError;
  String? _lastShownPlotsError;
  final List<PlotRecord> _plots = [];
  int? _plotsFarmId;
  int _plotsRequestId = 0;

  bool _plantingsLoading = false;
  String? _plantingsError;
  String? _lastShownPlantingsError;
  final List<PlantingRecord> _plantings = [];
  int? _plantingsPlotId;
  int _plantingsRequestId = 0;
  bool _initialFarmSyncTriggered = false;
  FarmContextProvider? _farmContext;
  final List<Map<String, dynamic>> _crops = [];
  final List<Map<String, dynamic>> _regions = [];
  static const List<String> _farmTypes = ['crop', 'mixed', 'livestock'];
  static const List<String> _soilTypes = ['clay', 'sandy', 'loam', 'silty', 'peaty', 'chalky', 'unknown'];
  static const List<String> _plantingStatuses = ['planned', 'active', 'harvested', 'failed'];

  InputDecoration _compactFieldDecoration(
    String label, {
    String? errorText,
    Widget? suffixIcon,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      hintText: hintText,
      border: const OutlineInputBorder(),
      isDense: true,
    );
  }

  @override
  void initState() {
    super.initState();
    syncRefreshNotifier.addListener(_handleSyncRefresh);
    _loadAlertsAndReports();
    _loadCrops();
    _loadRegions();
    _primeFarmCache();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _farmContext = Provider.of<FarmContextProvider>(context, listen: false);
      _farmContext?.addListener(_handleSelectionChange);
      _handleSelectionChange();
    });
  }

  @override
  void dispose() {
    syncRefreshNotifier.removeListener(_handleSyncRefresh);
    _farmContext?.removeListener(_handleSelectionChange);
    super.dispose();
  }

  void _handleSyncRefresh() {
    if (!mounted) return;
    unawaited(_reloadVisibleDataAfterSync());
  }

  Future<void> _reloadVisibleDataAfterSync() async {
    await _loadAlertsAndReports();
    await _loadCrops();
    await _loadRegions();
    await _loadFarms(clearExisting: false, refreshFromServer: false);
    final farmId = _plotsFarmId;
    if (farmId != null) {
      await _loadPlots(farmId);
    }
    final plotId = _plantingsPlotId;
    if (plotId != null) {
      await _loadPlantings(plotId);
    }
  }

  void _handleSelectionChange() {
    if (!mounted) return;
    final farm = _farmContext?.selectedFarm;
    final plot = _farmContext?.selectedPlot;

    if (farm == null) {
      _plotsRequestId += 1;
      _plantingsRequestId += 1;
      _plotsFarmId = null;
      _plantingsPlotId = null;
      _plotsLoading = false;
      _plantingsLoading = false;
      _plots.clear();
      _plantings.clear();
      _plotsError = null;
      _plantingsError = null;
      _lastShownPlotsError = null;
      _lastShownPlantingsError = null;
      if (!_farmsLoading && !_initialFarmSyncTriggered) {
        _initialFarmSyncTriggered = true;
        _loadFarms(clearExisting: _farms.isEmpty);
      }
      return;
    }

    if (_plotsFarmId != farm.id) {
      _plantingsRequestId += 1;
      _plotsFarmId = farm.id;
      _plantingsPlotId = null;
      _plantingsLoading = false;
      _plots.clear();
      _plantings.clear();
      _plotsError = null;
      _plantingsError = null;
      _lastShownPlotsError = null;
      _lastShownPlantingsError = null;
      _loadPlots(farm.id);
      return;
    }

    if (plot == null) return;

    if (_plantingsPlotId != plot.id) {
      _plantingsPlotId = plot.id;
      _plantings.clear();
      _plantingsError = null;
      _lastShownPlantingsError = null;
      _loadPlantings(plot.id);
    }
  }

  Future<void> _loadAlertsAndReports() async {
    await _loadCachedAlertsAndReports();
    try {
      final alerts = await ApiClient.getAlerts();
      final reports = await ApiClient.getDiseaseReports();
      await LocalCacheStore.instance.write(
        _alertsCacheKey,
        alerts.map(_alertToJson).toList(growable: false),
      );
      await LocalCacheStore.instance.write(
        _reportsCacheKey,
        reports.map(_diseaseReportToJson).toList(growable: false),
      );
      setAlerts(alerts);
      setDiseaseReports(reports);
      if (mounted) setState(() {});
    } on ApiUnauthorized {
      _redirectToLogin();
    } catch (_) {
      // Silently ignore alert load errors to avoid blocking core flow
    }
  }

  Future<void> _loadCrops() async {
    final cached = await LocalCacheStore.instance.readList(_cropsCacheKey);
    final cachedItems = (cached ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
    final initialItems = ReferenceData.mergeByIdThenName(
      cachedItems,
      ReferenceData.crops,
    );
    if (mounted) {
      setState(() {
        _crops
          ..clear()
          ..addAll(initialItems);
      });
    }
    try {
      var page = 1;
      const perPage = 200;
      final serverCrops = <Map<String, dynamic>>[];
      while (true) {
        final batch = await ApiClient.getCrops(page: page, perPage: perPage);
        serverCrops.addAll(batch);
        if (batch.length < perPage) break;
        page += 1;
      }
      _crops
        ..clear()
        ..addAll(ReferenceData.mergeByIdThenName(serverCrops, ReferenceData.crops));
      await LocalCacheStore.instance.write(_cropsCacheKey, _crops);
      if (mounted) setState(() {});
    } on ApiUnauthorized {
      _redirectToLogin();
    } catch (_) {
      // Crop list is optional; ignore errors and fall back to manual entry.
    }
  }

  Future<void> _loadRegions() async {
    final cached = await LocalCacheStore.instance.readList(_regionsCacheKey);
    final cachedItems = (cached ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
    final initialItems = ReferenceData.mergeByIdThenName(
      cachedItems,
      ReferenceData.regions,
    );
    if (mounted) {
      setState(() {
        _regions
          ..clear()
          ..addAll(initialItems);
      });
    }
    try {
      var page = 1;
      const perPage = 200;
      final serverRegions = <Map<String, dynamic>>[];
      while (true) {
        final batch = await ApiClient.getRegions(page: page, perPage: perPage);
        serverRegions.addAll(batch);
        if (batch.length < perPage) break;
        page += 1;
      }
      _regions
        ..clear()
        ..addAll(ReferenceData.mergeByIdThenName(serverRegions, ReferenceData.regions));
      await LocalCacheStore.instance.write(_regionsCacheKey, _regions);
      if (mounted) setState(() {});
    } on ApiUnauthorized {
      _redirectToLogin();
    } catch (_) {
      // Optional list; ignore errors and fall back to manual entry.
    }
  }

  void _redirectToLogin() {
    if (_isRedirecting || !mounted) return;
    _isRedirecting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    });
  }

  String _regionDisplayName(Map<String, dynamic> region) {
    final name = region['name']?.toString().trim() ?? '';
    final level = region['level']?.toString().trim();
    final parentId = _intValue(region['parent_id']);
    if (parentId == null) {
      return name;
    }
    final parent = _regions.where((item) => _intValue(item['id']) == parentId);
    if (parent.isEmpty) {
      return level == null || level.isEmpty ? name : '$name ($level)';
    }
    final parentName = parent.first['name']?.toString().trim() ?? '';
    return parentName.isEmpty ? name : '$name - $parentName';
  }

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Set<int> _descendantRegionIds(Iterable<int> seedIds) {
    final seeds = seedIds.where((id) => id > 0).toSet();
    if (seeds.isEmpty) return <int>{};

    final childrenByParent = <int, List<int>>{};
    for (final region in _regions) {
      final id = _intValue(region['id']);
      final parentId = _intValue(region['parent_id']);
      if (id == null || parentId == null) continue;
      childrenByParent.putIfAbsent(parentId, () => <int>[]).add(id);
    }

    final scoped = <int>{...seeds};
    final queue = <int>[...seeds];
    while (queue.isNotEmpty) {
      final parentId = queue.removeAt(0);
      for (final childId in childrenByParent[parentId] ?? const <int>[]) {
        if (scoped.add(childId)) {
          queue.add(childId);
        }
      }
    }
    return scoped;
  }

  List<Map<String, dynamic>> _availableFarmRegions({FarmRecord? editingFarm}) {
    final scopedRegionIds = _descendantRegionIds(
      _farms
          .map((farm) => farm.regionId)
          .followedBy(editingFarm == null ? const <int>[] : <int>[editingFarm.regionId]),
    );

    return _regions
        .where((r) => r['is_active'] == null || r['is_active'] == 1)
        .where((r) {
          if (scopedRegionIds.isEmpty) return true;
          final id = _intValue(r['id']);
          return id != null && scopedRegionIds.contains(id);
        })
        .map((r) => <String, dynamic>{
              ...r,
              'display_name': _regionDisplayName(r),
            })
        .toList();
  }

  int? _defaultFarmRegionId(FarmRecord? farm, List<Map<String, dynamic>> availableRegions) {
    if (farm != null) return farm.regionId;
    if (availableRegions.length == 1) {
      return _intValue(availableRegions.first['id']);
    }
    final existingRegionIds = _farms.map((item) => item.regionId).where((id) => id > 0).toSet();
    if (existingRegionIds.length == 1) {
      final onlyRegionId = existingRegionIds.first;
      if (availableRegions.any((item) => _intValue(item['id']) == onlyRegionId)) {
        return onlyRegionId;
      }
    }
    return null;
  }

  void _showSuccessMessage(
    String message, {
    String? nextStep,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          nextStep == null || nextStep.trim().isEmpty ? message : '$message\n$nextStep',
        ),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                onPressed: onAction,
              ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _loadCachedAlertsAndReports() async {
    final cachedAlerts = await LocalCacheStore.instance.readList(_alertsCacheKey);
    final cachedReports = await LocalCacheStore.instance.readList(_reportsCacheKey);
    final alerts = (cachedAlerts ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => AlertModel.fromJson(item.cast<String, dynamic>()))
        .toList();
    final reports = (cachedReports ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => DiseaseReportModel.fromJson(item.cast<String, dynamic>()))
        .toList();
    if (alerts.isNotEmpty) {
      setAlerts(alerts);
    }
    if (reports.isNotEmpty) {
      setDiseaseReports(reports);
    }
    if (mounted && (alerts.isNotEmpty || reports.isNotEmpty)) {
      setState(() {});
    }
  }

  Map<String, dynamic> _alertToJson(AlertModel alert) {
    return <String, dynamic>{
      'id': alert.id,
      'disease_report_id': alert.diseaseReportId,
      'alert_type': alert.alertType,
      'severity': alert.severity,
      'title': alert.title,
      'message': alert.message,
      'status': alert.status,
      'triggered_at': alert.triggeredAt.toIso8601String(),
    };
  }

  Map<String, dynamic> _diseaseReportToJson(DiseaseReportModel report) {
    return <String, dynamic>{
      'id': report.id,
      'plot_id': report.plotId,
      'crop_id': report.cropId,
      'planting_id': report.plantingId,
      'disease_name': report.diseaseName,
      'severity': report.severity,
      'confidence_score': report.confidenceScore,
      'description': report.description,
      'status': report.status,
      'reported_at': report.reportedAt.toIso8601String(),
      'treatment_guidance': report.treatmentGuidance == null
          ? null
          : <String, dynamic>{
              'mode': report.treatmentGuidance!.mode,
              'treatment_ready': report.treatmentGuidance!.treatmentReady,
              'review_status': report.treatmentGuidance!.reviewStatus,
              'expert_verified': report.treatmentGuidance!.expertVerified,
              'verification_note': report.treatmentGuidance!.verificationNote,
              'reliability': report.treatmentGuidance!.reliability,
              'risk_level': report.treatmentGuidance!.riskLevel,
              'confidence_score': report.treatmentGuidance!.confidenceScore,
              'crop_family': report.treatmentGuidance!.cropFamily,
              'headline': report.treatmentGuidance!.headline,
              'next_step': report.treatmentGuidance!.nextStep,
              'active_ingredient': report.treatmentGuidance!.activeIngredient,
              'dosage': report.treatmentGuidance!.dosage,
              'ppe': report.treatmentGuidance!.ppe,
              'pre_harvest_interval': report.treatmentGuidance!.preHarvestInterval,
              're_entry_interval': report.treatmentGuidance!.reEntryInterval,
              'actions': report.treatmentGuidance!.actions,
              'monitoring': report.treatmentGuidance!.monitoring,
              'prevention': report.treatmentGuidance!.prevention,
              'escalate_if': report.treatmentGuidance!.escalateIf,
              'notes': report.treatmentGuidance!.notes,
            },
      'inference_failure': report.inferenceFailure == null || !report.inferenceFailure!.hasFailure
          ? null
          : <String, dynamic>{
              'code': report.inferenceFailure!.code,
              'gate': report.inferenceFailure!.gate,
              'selected': report.inferenceFailure!.selected,
              'detected': report.inferenceFailure!.detected,
              'message': report.inferenceFailure!.message,
              'confidence_score': report.inferenceFailure!.confidenceScore,
              'occurred_at': report.inferenceFailure!.occurredAt?.toIso8601String(),
            },
    };
  }

  void _showScopedErrorOnce({
    required String scope,
    required String message,
    required VoidCallback onRetry,
  }) {
    final alreadyShown = switch (scope) {
      'farms' => _lastShownFarmsError,
      'plots' => _lastShownPlotsError,
      'plantings' => _lastShownPlantingsError,
      _ => null,
    };
    if (alreadyShown == message) return;

    switch (scope) {
      case 'farms':
        _lastShownFarmsError = message;
        break;
      case 'plots':
        _lastShownPlotsError = message;
        break;
      case 'plantings':
        _lastShownPlantingsError = message;
        break;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showErrorBanner(
        context,
        message: message,
        onRetry: () {
          switch (scope) {
            case 'farms':
              _lastShownFarmsError = null;
              break;
            case 'plots':
              _lastShownPlotsError = null;
              break;
            case 'plantings':
              _lastShownPlantingsError = null;
              break;
          }
          onRetry();
        },
      );
    });
  }

  Future<void> _primeFarmCache() async {
    final repo = OfflineRepository.instance;
    final farms = await repo.listFarms();
    if (!mounted || farms.isEmpty) return;
    final counts = await repo.plotCountsByFarm();
    setState(() {
      _farms
        ..clear()
        ..addAll(farms);
      _plotCounts
        ..clear()
        ..addAll(counts);
      _farmsError = null;
      _lastShownFarmsError = null;
    });
  }

  String _connectivityFriendlyMessage(String fallback) {
    return ApiClient.isConnectivityIssueMessage(fallback)
        ? L.t(LanguageStore.notifier.value, 'offline_saved_data_only')
        : fallback;
  }

  Future<void> _loadFarms({bool clearExisting = true, bool refreshFromServer = true}) async {
    if (_farmsLoading) return;
    final hadLocalData = _farms.isNotEmpty;

    setState(() {
      _farmsLoading = true;
      _farmsError = null;
      _lastShownFarmsError = null;
      if (clearExisting && !hadLocalData) {
        _farms.clear();
        _plotCounts.clear();
      }
    });

    final repo = OfflineRepository.instance;
    try {
      final localFarms = await repo.listFarms();
      final localCounts = await repo.plotCountsByFarm();
      if (!mounted) return;
      setState(() {
        _farms
          ..clear()
          ..addAll(localFarms);
        _plotCounts
          ..clear()
          ..addAll(localCounts);
        _farmsLoading = false;
        _farmsError = null;
      });

      if (!refreshFromServer) return;

      unawaited(() async {
        try {
          await OfflineSyncService.instance
              .syncNow(force: true, pullFirst: true)
              .timeout(const Duration(seconds: 12));
          final refreshed = await repo.listFarms();
          final refreshedCounts = await repo.plotCountsByFarm();
          if (!mounted) return;
          setState(() {
            _farms
              ..clear()
              ..addAll(refreshed);
            _plotCounts
              ..clear()
              ..addAll(refreshedCounts);
            _farmsError = null;
          });
        } catch (_) {
          // Keep local data visible instead of blocking the screen on sync.
        }
      }());
    } on ApiUnauthorized {
      if (!mounted) return;
      setState(() {
        _farmsLoading = false;
      });
      _redirectToLogin();
    } on ApiException catch (e) {
      if (!mounted) return;
      final hasLocal = _farms.isNotEmpty;
      setState(() {
        _farmsLoading = false;
        _farmsError = hasLocal ? null : _connectivityFriendlyMessage(e.message);
      });
    } catch (_) {
      if (!mounted) return;
      final hasLocal = _farms.isNotEmpty;
      setState(() {
        _farmsLoading = false;
        _farmsError = hasLocal ? null : L.t(LanguageStore.notifier.value, 'offline_saved_data_only');
      });
    }
  }

  Future<void> _loadPlots(int farmId) async {
    final requestId = ++_plotsRequestId;
    final repo = OfflineRepository.instance;
    final cachedPlots = await repo.listPlotsByFarmLocalId(farmId);

    if (!mounted || requestId != _plotsRequestId) return;
    setState(() {
      _plotsLoading = cachedPlots.isEmpty;
      _plotsError = null;
      _lastShownPlotsError = null;
      _plotsFarmId = farmId;
      _plots
        ..clear()
        ..addAll(cachedPlots);
      if (cachedPlots.isNotEmpty) {
        _plotCounts[farmId] = cachedPlots.length;
      }
    });
    setPlotFarmMap({
      for (final p in cachedPlots)
        if (p.serverId != null && p.farmServerId != null) p.serverId!: p.farmServerId!,
    });

    try {
      unawaited(() async {
        try {
          await OfflineSyncService.instance.syncNow().timeout(const Duration(seconds: 12));
          final loadedPlots = await repo.listPlotsByFarmLocalId(farmId);
          if (requestId != _plotsRequestId || !mounted) return;
          setPlotFarmMap({
            for (final p in loadedPlots)
              if (p.serverId != null && p.farmServerId != null) p.serverId!: p.farmServerId!,
          });
          setState(() {
            _plots
              ..clear()
              ..addAll(loadedPlots);
            _plotCounts[farmId] = loadedPlots.length;
            _plotsLoading = false;
            _plotsError = null;
          });
        } catch (_) {
          if (requestId != _plotsRequestId || !mounted) return;
          setState(() {
            _plotsLoading = false;
          });
        }
      }());
    } on ApiUnauthorized {
      if (requestId != _plotsRequestId || !mounted) return;
      setState(() {
        _plotsLoading = false;
      });
      _redirectToLogin();
    } on ApiException catch (e) {
      if (requestId != _plotsRequestId || !mounted) return;
      setState(() {
        _plotsLoading = false;
        _plotsError = _plots.isNotEmpty ? null : _connectivityFriendlyMessage(e.message);
      });
    } catch (_) {
      if (requestId != _plotsRequestId || !mounted) return;
      setState(() {
        _plotsLoading = false;
        _plotsError =
            _plots.isNotEmpty ? null : L.t(LanguageStore.notifier.value, 'offline_saved_data_only');
      });
    }
  }

  Future<void> _loadPlantings(int plotId) async {
    final requestId = ++_plantingsRequestId;
    final repo = OfflineRepository.instance;
    final cachedPlantings = await repo.listPlantingsByPlotLocalId(plotId);

    if (!mounted || requestId != _plantingsRequestId) return;
    setState(() {
      _plantingsLoading = cachedPlantings.isEmpty;
      _plantingsError = null;
      _lastShownPlantingsError = null;
      _plantingsPlotId = plotId;
      _plantings
        ..clear()
        ..addAll(cachedPlantings);
    });

    try {
      unawaited(() async {
        try {
          await OfflineSyncService.instance.syncNow().timeout(const Duration(seconds: 12));
          final loadedPlantings = await repo.listPlantingsByPlotLocalId(plotId);
          if (requestId != _plantingsRequestId || !mounted) return;
          setState(() {
            _plantings
              ..clear()
              ..addAll(loadedPlantings);
            _plantingsLoading = false;
            _plantingsError = null;
          });
        } catch (_) {
          if (requestId != _plantingsRequestId || !mounted) return;
          setState(() {
            _plantingsLoading = false;
          });
        }
      }());
    } on ApiUnauthorized {
      if (requestId != _plantingsRequestId || !mounted) return;
      setState(() {
        _plantingsLoading = false;
      });
      _redirectToLogin();
    } on ApiException catch (e) {
      if (requestId != _plantingsRequestId || !mounted) return;
      setState(() {
        _plantingsLoading = false;
        _plantingsError =
            _plantings.isNotEmpty ? null : _connectivityFriendlyMessage(e.message);
      });
    } catch (_) {
      if (requestId != _plantingsRequestId || !mounted) return;
      setState(() {
        _plantingsLoading = false;
        _plantingsError = _plantings.isNotEmpty
            ? null
            : L.t(LanguageStore.notifier.value, 'offline_saved_data_only');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        return Consumer<FarmContextProvider>(
          builder: (context, farmContext, _) {
            final selectedFarm = farmContext.selectedFarm;
            final selectedPlot = farmContext.selectedPlot;

            return PopScope(
              canPop: selectedFarm == null && selectedPlot == null,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                if (selectedPlot != null) {
                  farmContext.clearPlotSelection();
                  return;
                }
                if (selectedFarm != null) {
                  farmContext.clearSelection();
                }
              },
              child: FarmSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Expanded(
                      child: Builder(
                      builder: (_) {
                        if (selectedFarm == null) {
                          if (_farmsError != null) {
                            _showScopedErrorOnce(
                              scope: 'farms',
                              message: _farmsError!,
                              onRetry: _loadFarms,
                            );
                          }
                          if (_farmsLoading) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          return FarmListWidget(
                            farms: _farms,
                            plotCounts: _plotCounts,
                            onAdd: () => _showCreateFarmDialog(lang),
                            onEdit: (farm) => _showEditFarmDialog(farm, lang),
                            onDelete: (farm) => _confirmDeleteFarm(farm, lang),
                          );
                        }

                        if (selectedPlot == null) {
                          if (_plotsError != null) {
                            _showScopedErrorOnce(
                              scope: 'plots',
                              message: _plotsError!,
                              onRetry: () => _loadPlots(selectedFarm.id),
                            );
                          }
                          if (_plotsLoading) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          return PlotListWidget(
                            farm: selectedFarm,
                            plots: _plots,
                            onAdd: () => _showCreatePlotDialog(selectedFarm.id, lang),
                            onEdit: (plot) => _showEditPlotDialog(plot, lang),
                            onDelete: (plot) => _confirmDeletePlot(plot, lang),
                          );
                        }

                        if (_plantingsError != null) {
                          _showScopedErrorOnce(
                            scope: 'plantings',
                            message: _plantingsError!,
                            onRetry: () => _loadPlantings(selectedPlot.id),
                          );
                        }
                        if (_plantingsLoading) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        return PlantingListWidget(
                          plot: selectedPlot,
                          plantings: _plantings,
                          cropNameForId: _cropNameForId,
                          onAdd: () => _showCreatePlantingDialog(selectedPlot.id, lang),
                          onEdit: (planting) => _showEditPlantingDialog(planting, lang),
                          onDelete: (planting) => _confirmDeletePlanting(planting, lang),
                          onPredictYield: (planting) => _openYieldPrediction(selectedPlot, planting),
                        );
                      },
                    ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCreateFarmDialog(String lang) {
    _showFarmDialog(lang: lang);
  }

  void _showEditFarmDialog(FarmRecord farm, String lang) {
    _showFarmDialog(farm: farm, lang: lang);
  }

  Future<void> _showFarmDialog({required String lang, FarmRecord? farm}) async {
    final nameController = TextEditingController(text: farm?.farmName ?? '');
    final regionController =
        TextEditingController(text: farm?.regionId.toString() ?? '');
    final latController =
        TextEditingController(text: farm?.latitude?.toString() ?? '');
    final lonController =
        TextEditingController(text: farm?.longitude?.toString() ?? '');
    final areaController =
        TextEditingController(text: farm?.areaHectares?.toString() ?? '');
    String? selectedFarmType = farm?.farmType;
    bool isActive = farm?.isActive ?? true;
    final availableRegions = _availableFarmRegions(editingFarm: farm);
    int? selectedRegionId = _defaultFarmRegionId(farm, availableRegions);
    String? farmNameError;
    String? regionError;
    String? formError;
    bool saving = false;
    bool fetchingLocation = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> fillCurrentLocation() async {
              setDialogState(() {
                formError = null;
                fetchingLocation = true;
              });

              try {
                final serviceEnabled = await Geolocator.isLocationServiceEnabled();
                if (!serviceEnabled) {
                  setDialogState(() {
                    fetchingLocation = false;
                    formError = L.t(lang, 'my_farm_location_disabled');
                  });
                  return;
                }

                var permission = await Geolocator.checkPermission();
                if (permission == LocationPermission.denied) {
                  permission = await Geolocator.requestPermission();
                }
                if (permission == LocationPermission.denied ||
                    permission == LocationPermission.deniedForever) {
                  setDialogState(() {
                    fetchingLocation = false;
                    formError = L.t(lang, 'my_farm_location_permission_required');
                  });
                  return;
                }

                final position = await Geolocator.getCurrentPosition(
                  locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.best,
                  ),
                );

                setDialogState(() {
                  latController.text = position.latitude.toStringAsFixed(7);
                  lonController.text = position.longitude.toStringAsFixed(7);
                  fetchingLocation = false;
                });
              } catch (_) {
                setDialogState(() {
                  fetchingLocation = false;
                  formError = L.t(lang, 'my_farm_location_fetch_failed');
                });
              }
            }

            return _FarmerFormDialog(
              title: farm == null ? L.t(lang, 'add_farm') : L.t(lang, 'edit_farm'),
              primaryAction: ElevatedButton(
                onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() {
                            farmNameError = null;
                            regionError = null;
                            formError = null;
                          });

                          final name = nameController.text.trim();
                          final regionId =
                              selectedRegionId ?? int.tryParse(regionController.text.trim());

                          var hasValidationError = false;
                          if (name.isEmpty) {
                            farmNameError = L.t(lang, 'my_farm_error_farm_name_required');
                            hasValidationError = true;
                          }
                          if (regionId == null) {
                            regionError = L.t(lang, 'my_farm_error_region_required');
                            hasValidationError = true;
                          }
                          if (hasValidationError) {
                            setDialogState(() {});
                            return;
                          }

                          final latitude = double.tryParse(latController.text.trim());
                          final longitude = double.tryParse(lonController.text.trim());
                          final area = double.tryParse(areaController.text.trim());
                          final farmType = selectedFarmType;

                          setDialogState(() {
                            saving = true;
                          });

                          try {
                            final repo = OfflineRepository.instance;
                            FarmRecord? savedFarm;
                            if (farm == null) {
                              savedFarm = await repo.createFarmLocal(
                                regionId: regionId!,
                                farmName: name,
                                latitude: latitude,
                                longitude: longitude,
                                areaHectares: area,
                                farmType: farmType,
                                isActive: isActive,
                              );
                            } else {
                              await repo.updateFarmLocal(
                                localId: farm.localId,
                                regionId: regionId!,
                                farmName: name,
                                latitude: latitude,
                                longitude: longitude,
                                areaHectares: area,
                                farmType: farmType,
                                isActive: isActive,
                              );
                            }
                            unawaited(OfflineSyncService.instance.syncNow().catchError((_) {}));
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            if (!mounted) return;
                            _loadFarms(clearExisting: false, refreshFromServer: false);
                            _showSuccessMessage(
                              farm == null ? L.t(lang, 'my_farm_success_farm_added') : L.t(lang, 'my_farm_success_farm_updated'),
                              nextStep: farm == null
                                  ? L.t(lang, 'action_next_farm_added')
                                  : L.t(lang, 'action_next_farm_updated'),
                              actionLabel: savedFarm == null ? null : L.t(lang, 'add_plot'),
                              onAction: savedFarm == null
                                  ? null
                                  : () {
                                      _farmContext?.setFarm(savedFarm!);
                                      _showCreatePlotDialog(savedFarm!.localId, lang);
                                    },
                            );
                          } on ApiUnauthorized {
                            if (mounted) {
                              setDialogState(() {
                                saving = false;
                              });
                            }
                            _redirectToLogin();
                          } on ApiException catch (e) {
                            setDialogState(() {
                              saving = false;
                              formError = e.message;
                            });
                          } catch (_) {
                            setDialogState(() {
                              saving = false;
                              formError = L.t(lang, 'farm_save_failed');
                            });
                          }
                        },
                child: saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(L.t(lang, 'save')),
              ),
              secondaryAction: TextButton(
                onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                child: Text(L.t(lang, 'cancel')),
              ),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: _compactFieldDecoration(
                        L.t(lang, 'farm_name'),
                        errorText: farmNameError,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (availableRegions.isNotEmpty)
                      InkWell(
                        onTap: () async {
                          final picked = await _showSearchPicker(
                            title: L.t(lang, 'select_region'),
                            items: availableRegions,
                            labelKey: 'display_name',
                            idKey: 'id',
                          );
                          if (picked != null) {
                            setDialogState(() {
                              selectedRegionId = picked['id'] as int;
                              regionController.text = selectedRegionId.toString();
                              regionError = null;
                            });
                          }
                        },
                        child: InputDecorator(
                          decoration: _compactFieldDecoration(
                            L.t(lang, 'region'),
                            errorText: regionError,
                          ),
                          child: Text(
                            availableRegions
                                    .firstWhere(
                                      (r) => r['id'] == selectedRegionId,
                                      orElse: () => {},
                                    )['display_name']
                                    ?.toString() ??
                                L.t(lang, 'select_region'),
                          ),
                        ),
                      )
                    else
                      TextField(
                        controller: regionController,
                        keyboardType: TextInputType.number,
                        decoration: _compactFieldDecoration(
                          L.t(lang, 'region_id'),
                          errorText: regionError,
                        ),
                      ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: (saving || fetchingLocation)
                            ? null
                            : () => fillCurrentLocation(),
                        icon: fetchingLocation
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location_outlined),
                        label: Text(
                          fetchingLocation ? L.t(lang, 'my_farm_location_getting') : L.t(lang, 'my_farm_location_use_current'),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: latController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: _compactFieldDecoration(L.t(lang, 'latitude')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: lonController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: _compactFieldDecoration(L.t(lang, 'longitude')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: areaController,
                      keyboardType: TextInputType.number,
                      decoration: _compactFieldDecoration(L.t(lang, 'area_hectares')),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _farmTypes.contains(selectedFarmType) ? selectedFarmType : null,
                      decoration: _compactFieldDecoration(L.t(lang, 'farm_type')),
                      items: _farmTypes
                          .map((value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(LocalizedValue.farmType(lang, value)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedFarmType = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      value: isActive,
                      contentPadding: EdgeInsets.zero,
                      title: Text(L.t(lang, 'active')),
                      onChanged: (value) {
                        setDialogState(() {
                          isActive = value;
                        });
                      },
                    ),
                    if (formError != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            formError!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      ),
                  ],
                ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteFarm(FarmRecord farm, String lang) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L.t(lang, 'delete_farm')),
        content: Text(
          L.t(lang, 'delete_farm_confirm', params: {'farm': farm.farmName}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(L.t(lang, 'cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(L.t(lang, 'delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await OfflineRepository.instance.deleteFarmLocal(farm.localId);
      unawaited(OfflineSyncService.instance.syncNow().catchError((_) {}));
      if (!mounted) return;
      if (_farmContext?.selectedFarm?.id == farm.id) {
        _farmContext?.clearSelection();
      }
      _loadFarms(clearExisting: false, refreshFromServer: false);
      _showSuccessMessage(
        L.t(lang, 'my_farm_success_farm_deleted'),
        nextStep: L.t(lang, 'action_next_farm_deleted'),
      );
    } on ApiUnauthorized {
      _redirectToLogin();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorBanner(context, message: e.message);
    } catch (_) {
      if (!mounted) return;
      showErrorBanner(context, message: L.t(lang, 'farm_delete_failed'));
    }
  }

  void _showCreatePlotDialog(int farmId, String lang) {
    _showPlotDialog(farmId: farmId, lang: lang);
  }

  void _showEditPlotDialog(PlotRecord plot, String lang) {
    final farmId = plot.farmLocalId ?? plot.farmServerId ?? 0;
    _showPlotDialog(farmId: farmId, plot: plot, lang: lang);
  }

  Future<void> _showPlotDialog({
    required int farmId,
    required String lang,
    PlotRecord? plot,
  }) async {
    final nameController = TextEditingController(text: plot?.plotName ?? '');
    final areaController =
        TextEditingController(text: plot?.areaHectares?.toString() ?? '');
    String? selectedSoilType =
        (plot?.soilType.trim().isEmpty ?? true) ? null : plot?.soilType.trim();
    String? plotNameError;
    String? formError;
    bool isActive = plot?.isActive ?? true;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return _FarmerFormDialog(
              title: plot == null ? L.t(lang, 'add_plot') : L.t(lang, 'edit_plot'),
              primaryAction: ElevatedButton(
                onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() {
                            plotNameError = null;
                            formError = null;
                          });

                          final name = nameController.text.trim();
                          if (name.isEmpty) {
                            setDialogState(() {
                              plotNameError = L.t(lang, 'my_farm_error_plot_name_required');
                            });
                            return;
                          }

                          final area = double.tryParse(areaController.text.trim());
                          final soilType = selectedSoilType ?? '';

                          setDialogState(() {
                            saving = true;
                          });

                          try {
                            final repo = OfflineRepository.instance;
                            PlotRecord? savedPlot;
                            if (plot == null) {
                              savedPlot = await repo.createPlotLocal(
                                farmLocalId: farmId,
                                plotName: name,
                                areaHectares: area,
                                soilType: soilType,
                                isActive: isActive,
                              );
                            } else {
                              await repo.updatePlotLocal(
                                localId: plot.localId,
                                plotName: name,
                                areaHectares: area,
                                soilType: soilType,
                                isActive: isActive,
                              );
                            }
                            unawaited(OfflineSyncService.instance.syncNow().catchError((_) {}));
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            if (!mounted) return;
                            _loadPlots(farmId);
                            _showSuccessMessage(
                              plot == null ? L.t(lang, 'my_farm_success_plot_added') : L.t(lang, 'my_farm_success_plot_updated'),
                              nextStep: plot == null
                                  ? L.t(lang, 'action_next_plot_added')
                                  : L.t(lang, 'action_next_plot_updated'),
                              actionLabel: savedPlot == null ? null : L.t(lang, 'add_planting'),
                              onAction: savedPlot == null
                                  ? null
                                  : () {
                                      _farmContext?.setPlot(savedPlot!);
                                      _showCreatePlantingDialog(savedPlot!.localId, lang);
                                    },
                            );
                          } on ApiUnauthorized {
                            if (mounted) {
                              setDialogState(() {
                                saving = false;
                              });
                            }
                            _redirectToLogin();
                          } on ApiException catch (e) {
                            setDialogState(() {
                              saving = false;
                              formError = e.message;
                            });
                          } catch (_) {
                            setDialogState(() {
                              saving = false;
                              formError = L.t(lang, 'plot_save_failed');
                            });
                          }
                        },
                child: saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(L.t(lang, 'save')),
              ),
              secondaryAction: TextButton(
                onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                child: Text(L.t(lang, 'cancel')),
              ),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: _compactFieldDecoration(
                        L.t(lang, 'plot_name'),
                        errorText: plotNameError,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: areaController,
                      keyboardType: TextInputType.number,
                      decoration: _compactFieldDecoration(L.t(lang, 'area_hectares')),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _soilTypes.contains(selectedSoilType) ? selectedSoilType : null,
                      decoration: _compactFieldDecoration(L.t(lang, 'soil_type')),
                      items: _soilTypes
                          .map((value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(LocalizedValue.soilType(lang, value)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedSoilType = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      value: isActive,
                      contentPadding: EdgeInsets.zero,
                      title: Text(L.t(lang, 'active')),
                      onChanged: (value) {
                        setDialogState(() {
                          isActive = value;
                        });
                      },
                    ),
                    if (formError != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            formError!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      ),
                  ],
                ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeletePlot(PlotRecord plot, String lang) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L.t(lang, 'delete_plot')),
        content: Text(
          L.t(lang, 'delete_plot_confirm', params: {'plot': plot.plotName}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(L.t(lang, 'cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(L.t(lang, 'delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await OfflineRepository.instance.deletePlotLocal(plot.localId);
      unawaited(OfflineSyncService.instance.syncNow().catchError((_) {}));
      if (!mounted) return;
      if (_farmContext?.selectedPlot?.id == plot.id) {
        _farmContext?.clearPlotSelection();
      }
      if (plot.farmLocalId != null) {
        _loadPlots(plot.farmLocalId!);
      }
      _showSuccessMessage(
        L.t(lang, 'my_farm_success_plot_deleted'),
        nextStep: L.t(lang, 'action_next_plot_deleted'),
      );
    } on ApiUnauthorized {
      _redirectToLogin();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorBanner(context, message: e.message);
    } catch (_) {
      if (!mounted) return;
      showErrorBanner(context, message: L.t(lang, 'plot_delete_failed'));
    }
  }

  void _showCreatePlantingDialog(int plotId, String lang) {
    _showPlantingDialog(plotId: plotId, lang: lang);
  }

  String _cropNameForId(int cropId) {
    for (final crop in _crops) {
      final id = crop['id'];
      final parsedId = id is int ? id : int.tryParse(id?.toString() ?? '');
      if (parsedId == cropId) {
        final name = crop['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          return LocalizedValue.crop(LanguageStore.notifier.value, name);
        }
      }
    }
    return '${LocalizedValue.fixed(LanguageStore.notifier.value, 'crop_short')} #$cropId';
  }

  Future<void> _openYieldPrediction(PlotRecord plot, PlantingRecord planting) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => YieldPredictionScreen(
          plot: plot,
          planting: planting,
          cropLabel: _cropNameForId(planting.cropId),
        ),
      ),
    );
  }

  void _showEditPlantingDialog(PlantingRecord planting, String lang) {
    final plotId = planting.plotLocalId ?? planting.plotServerId ?? 0;
    _showPlantingDialog(plotId: plotId, planting: planting, lang: lang);
  }

  Future<void> _showPlantingDialog({
    required int plotId,
    required String lang,
    PlantingRecord? planting,
  }) async {
    String formatDate(DateTime value) {
      final y = value.year.toString().padLeft(4, '0');
      final m = value.month.toString().padLeft(2, '0');
      final d = value.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    final cropController =
        TextEditingController(text: planting?.cropId.toString() ?? '');
    final plantingDateController =
        TextEditingController(text: planting == null ? '' : formatDate(planting.plantingDate));
    final expectedInitialDate = planting?.expectedHarvestDate;
    final expectedDateController = TextEditingController(
      text: expectedInitialDate == null ? '' : formatDate(expectedInitialDate),
    );
    String? selectedStatus =
        (planting?.status.trim().isEmpty ?? true) ? null : planting?.status.trim();
    bool isActive = planting?.isActive ?? true;
    int? selectedCropId = planting?.cropId;
    String? cropError;
    String? plantingDateError;
    String? expectedDateError;
    String? formError;
    bool saving = false;

    final availableCrops = filterSupportedCropEntries(
      _crops.where((c) => c['is_active'] == null || c['is_active'] == 1).toList(),
    );
    final availableCropIds = supportedCropIds(availableCrops);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickDate(TextEditingController controller) async {
              final now = DateTime.now();
              final initial = DateTime.tryParse(controller.text.trim()) ?? now;
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: initial,
                firstDate: DateTime(now.year - 20),
                lastDate: DateTime(now.year + 20),
              );
              if (picked != null) {
                setDialogState(() {
                  controller.text = formatDate(picked);
                  if (controller == plantingDateController) {
                    plantingDateError = null;
                  }
                  if (controller == expectedDateController) {
                    expectedDateError = null;
                  }
                });
              }
            }

            return _FarmerFormDialog(
              title: planting == null ? L.t(lang, 'add_planting') : L.t(lang, 'edit_planting'),
              primaryAction: ElevatedButton(
                onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() {
                            cropError = null;
                            plantingDateError = null;
                            expectedDateError = null;
                            formError = null;
                          });

                          final cropId = selectedCropId ?? int.tryParse(cropController.text.trim());
                          final plantingDateRaw = plantingDateController.text.trim();
                          final expectedDateRaw = expectedDateController.text.trim();
                          final plantingDate = DateTime.tryParse(plantingDateRaw);
                          final expectedDate = expectedDateRaw.isEmpty
                              ? null
                              : DateTime.tryParse(expectedDateRaw);

                          var hasValidationError = false;
                          if (cropId == null) {
                            cropError = L.t(lang, 'my_farm_error_crop_required');
                            hasValidationError = true;
                          } else if (!availableCropIds.contains(cropId)) {
                            cropError = L.t(lang, 'my_farm_error_crop_out_of_scope');
                            hasValidationError = true;
                          }
                          if (plantingDateRaw.isEmpty || plantingDate == null) {
                            plantingDateError = L.t(lang, 'my_farm_error_planting_date_required');
                            hasValidationError = true;
                          }
                          if (expectedDateRaw.isNotEmpty && expectedDate == null) {
                            expectedDateError = L.t(lang, 'my_farm_error_invalid_date');
                            hasValidationError = true;
                          }
                          if (hasValidationError) {
                            setDialogState(() {});
                            return;
                          }

                          final validCropId = cropId;
                          final validPlantingDate = plantingDate;
                          if (validCropId == null || validPlantingDate == null) {
                            setDialogState(() {
                              formError = L.t(lang, 'planting_required');
                            });
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                          });

                          final status = selectedStatus ?? '';

                          try {
                            final repo = OfflineRepository.instance;
                            PlantingRecord? savedPlanting;
                            if (planting == null) {
                              savedPlanting = await repo.createPlantingLocal(
                                plotLocalId: plotId,
                                cropId: validCropId,
                                plantingDate: validPlantingDate,
                                expectedHarvestDate: expectedDate,
                                status: status,
                                isActive: isActive,
                              );
                            } else {
                              await repo.updatePlantingLocal(
                                localId: planting.localId,
                                cropId: validCropId,
                                plantingDate: validPlantingDate,
                                expectedHarvestDate: expectedDate,
                                status: status,
                                isActive: isActive,
                              );
                            }
                            unawaited(OfflineSyncService.instance.syncNow().catchError((_) {}));
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            if (!mounted) return;
                            _loadPlantings(plotId);
                            _showSuccessMessage(
                              planting == null
                                  ? L.t(lang, 'my_farm_success_planting_added')
                                  : L.t(lang, 'my_farm_success_planting_updated'),
                              nextStep: planting == null
                                  ? L.t(lang, 'action_next_planting_added')
                                  : L.t(lang, 'action_next_planting_updated'),
                              actionLabel: savedPlanting == null ? null : L.t(lang, 'scan'),
                              onAction: savedPlanting == null
                                  ? null
                                  : () {
                                      _farmContext?.setPlanting(savedPlanting!);
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => const ScanScreen(),
                                        ),
                                      );
                                    },
                            );
                          } on ApiUnauthorized {
                            if (mounted) {
                              setDialogState(() {
                                saving = false;
                              });
                            }
                            _redirectToLogin();
                          } on ApiException catch (e) {
                            setDialogState(() {
                              saving = false;
                              formError = e.message;
                            });
                          } catch (_) {
                            setDialogState(() {
                              saving = false;
                              formError = L.t(lang, 'planting_save_failed');
                            });
                          }
                        },
                child: saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(L.t(lang, 'save')),
              ),
              secondaryAction: TextButton(
                onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                child: Text(L.t(lang, 'cancel')),
              ),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (availableCrops.isNotEmpty)
                      InkWell(
                        onTap: () async {
                          final picked = await _showSearchPicker(
                            title: L.t(lang, 'select_crop'),
                            items: availableCrops,
                            labelKey: 'name',
                            idKey: 'id',
                          );
                          if (picked != null) {
                            setDialogState(() {
                              selectedCropId = picked['id'] as int;
                              cropController.text = selectedCropId.toString();
                              cropError = null;
                            });
                          }
                        },
                        child: InputDecorator(
                          decoration: _compactFieldDecoration(
                            L.t(lang, 'crop'),
                            errorText: cropError,
                          ),
                          child: Text(
                            availableCrops
                                    .firstWhere(
                                      (c) => c['id'] == selectedCropId,
                                      orElse: () => {},
                                    )['name']
                                    ?.toString() ??
                                L.t(lang, 'select_crop'),
                          ),
                        ),
                      )
                    else
                      TextField(
                        controller: cropController,
                        keyboardType: TextInputType.number,
                        decoration: _compactFieldDecoration(
                          L.t(lang, 'crop_id'),
                          errorText: cropError,
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: plantingDateController,
                      readOnly: true,
                      onTap: () => pickDate(plantingDateController),
                      decoration: _compactFieldDecoration(
                        L.t(lang, 'planting_date'),
                        hintText: 'YYYY-MM-DD',
                        errorText: plantingDateError,
                        suffixIcon: IconButton(
                          onPressed: () => pickDate(plantingDateController),
                          icon: const Icon(Icons.calendar_today_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: expectedDateController,
                      readOnly: true,
                      onTap: () => pickDate(expectedDateController),
                      decoration: _compactFieldDecoration(
                        L.t(lang, 'expected_harvest_date'),
                        hintText: 'YYYY-MM-DD',
                        errorText: expectedDateError,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => setDialogState(() {
                                expectedDateController.clear();
                                expectedDateError = null;
                              }),
                              icon: const Icon(Icons.clear),
                            ),
                            IconButton(
                              onPressed: () => pickDate(expectedDateController),
                              icon: const Icon(Icons.calendar_today_outlined),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue:
                          _plantingStatuses.contains(selectedStatus) ? selectedStatus : null,
                      decoration: _compactFieldDecoration(L.t(lang, 'status_label')),
                      items: _plantingStatuses
                          .map((value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(LocalizedValue.status(lang, value)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedStatus = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      value: isActive,
                      contentPadding: EdgeInsets.zero,
                      title: Text(L.t(lang, 'active')),
                      onChanged: (value) {
                        setDialogState(() {
                          isActive = value;
                        });
                      },
                    ),
                    if (formError != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            formError!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      ),
                  ],
                ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeletePlanting(PlantingRecord planting, String lang) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L.t(lang, 'delete_planting')),
        content: Text(L.t(lang, 'delete_planting_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(L.t(lang, 'cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(L.t(lang, 'delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await OfflineRepository.instance.deletePlantingLocal(planting.localId);
      unawaited(OfflineSyncService.instance.syncNow().catchError((_) {}));
      if (!mounted) return;
      if (_farmContext?.selectedPlanting?.id == planting.id) {
        _farmContext?.clearPlotSelection();
      }
      if (planting.plotLocalId != null) {
        _loadPlantings(planting.plotLocalId!);
      }
      _showSuccessMessage(
        L.t(lang, 'my_farm_success_planting_deleted'),
        nextStep: L.t(lang, 'action_next_planting_deleted'),
      );
    } on ApiUnauthorized {
      _redirectToLogin();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorBanner(context, message: e.message);
    } catch (_) {
      if (!mounted) return;
      showErrorBanner(context, message: L.t(lang, 'planting_delete_failed'));
    }
  }

  Future<Map<String, dynamic>?> _showSearchPicker({
    required String title,
    required List<Map<String, dynamic>> items,
    required String labelKey,
    required String idKey,
  }) async {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> filtered = List<Map<String, dynamic>>.from(items);

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: StatefulBuilder(
              builder: (context, setState) {
                void applyFilter(String value) {
                  final q = value.trim().toLowerCase();
                  setState(() {
                    if (q.isEmpty) {
                      filtered = List<Map<String, dynamic>>.from(items);
                    } else {
                      filtered = items
                          .where(
                            (item) =>
                                item[labelKey]?.toString().toLowerCase().contains(q) ??
                                false,
                          )
                          .toList();
                    }
                  });
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: L.t(LanguageStore.notifier.value, 'search'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: const Icon(Icons.search),
                        ),
                        onChanged: applyFilter,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  LocalizedValue.fixed(
                                    LanguageStore.notifier.value,
                                    'no_matching_items_found',
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final label = item[labelKey]?.toString() ??
                                    LocalizedValue.fixed(
                                      LanguageStore.notifier.value,
                                      'unknown',
                                    );
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    title: Text(
                                      label,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.of(sheetContext).pop({
                                      'id': (item[idKey] as num).toInt(),
                                      'name': label,
                                    }),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _FarmerFormDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget primaryAction;
  final Widget secondaryAction;

  const _FarmerFormDialog({
    required this.title,
    required this.child,
    required this.primaryAction,
    required this.secondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: FarmSurface(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF2F5E12), Color(0xFF7EA120)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.agriculture_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: FarmPanel(child: child),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(child: secondaryAction),
                    const SizedBox(width: 12),
                    Expanded(child: primaryAction),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}






