import 'dart:async';

import '../api_client.dart';
import '../connectivity_status_service.dart';
import '../features/disease/disease_history_cache_store.dart';
import '../features/my_farm/models/farm_model.dart';
import '../features/my_farm/models/plot_model.dart';
import '../features/my_farm/models/planting_model.dart';
import 'offline_models.dart';
import 'offline_repository.dart';
import 'sync_state.dart';
import '../sync_refresh_notifier.dart';

class OfflineSyncService {
  OfflineSyncService._();

  static final OfflineSyncService instance = OfflineSyncService._();

  static const Duration _minSyncInterval = Duration(minutes: 2);
  bool _syncing = false;
  DateTime? _lastSyncAt;

  Future<void> syncNow({bool force = false, bool pullFirst = true}) async {
    if (_syncing) return;
    final now = DateTime.now();
    if (!force &&
        _lastSyncAt != null &&
        now.difference(_lastSyncAt!) < _minSyncInterval) {
      return;
    }

    _syncing = true;
    try {
      final status = await ConnectivityStatusService.instance.refreshNow();
      if (status.state != ApiConnectivityState.apiOnline) {
        return;
      }

      if (pullFirst) {
        await _pullServerData();
      }

      await _pushPendingChanges();
      _lastSyncAt = DateTime.now();
      notifySyncRefresh();
    } finally {
      _syncing = false;
    }
  }

  Future<void> _pullServerData() async {
    final repo = OfflineRepository.instance;

    try {
      await _pullDiseaseHistoryCache();
    } catch (_) {
      // Disease history cache is non-blocking; farm/soil sync must not fail
      // just because image-heavy history refresh is temporarily unavailable.
    }

    final farms = <FarmModel>[];
    var page = 1;
    const perPage = 50;
    while (true) {
      final result = await ApiClient.getFarmsWithCounts(page: page, perPage: perPage);
      farms.addAll(result.farms);
      if (result.farms.length < perPage) break;
      page += 1;
    }
    await repo.mergeFarmsFromServer(farms);

    for (final farm in farms) {
      final plots = <PlotModel>[];
      var plotPage = 1;
      while (true) {
        final batch = await ApiClient.getPlots(farm.id, page: plotPage, perPage: perPage);
        plots.addAll(batch);
        if (batch.length < perPage) break;
        plotPage += 1;
      }
      await repo.mergePlotsFromServer(farmServerId: farm.id, plots: plots);

      for (final plot in plots) {
        final plantings = <PlantingModel>[];
        var plantingPage = 1;
        const plantingPerPage = 100;
        while (true) {
          final batch = await ApiClient.getPlantings(
            plot.id,
            page: plantingPage,
            perPage: plantingPerPage,
          );
          plantings.addAll(batch);
          if (batch.length < plantingPerPage) break;
          plantingPage += 1;
        }
        await repo.mergePlantingsFromServer(
          plotServerId: plot.id,
          plantings: plantings,
        );
      }
    }

    final soilItems = <Map<String, dynamic>>[];
    var soilPage = 1;
    const soilPerPage = 50;
    while (true) {
      final pageResult =
          await ApiClient.getSoilHealthPage(page: soilPage, perPage: soilPerPage);
      soilItems.addAll(pageResult.items);
      if (pageResult.items.length < soilPerPage) break;
      soilPage += 1;
    }
    await repo.mergeSoilHealthFromServer(soilItems);
  }

  Future<void> _pullDiseaseHistoryCache() async {
    const diseasePerPage = 50;
    final pageResult = await ApiClient.getDiseaseReportsPage(
      page: 1,
      perPage: diseasePerPage,
    );
    await DiseaseHistoryCacheStore.instance.saveAll(pageResult.items);
  }

  Future<void> _pushPendingChanges() async {
    final repo = OfflineRepository.instance;

    await _pushFarms(repo);
    await _pushPlots(repo);
    await _pushPlantings(repo);
    await _pushSoilHealth(repo);
  }

  bool _hasConflict(DateTime? baseServer, DateTime? remoteServer) {
    if (baseServer == null || remoteServer == null) return false;
    return remoteServer.isAfter(baseServer);
  }

  bool _missingServerVersion(DateTime? baseServer, DateTime? remoteServer) {
    return baseServer != null && remoteServer == null;
  }

  bool _isTransientSyncError(ApiException error) {
    if (error is ApiForbidden || error is ApiUnauthorized) return false;
    final message = error.message.toLowerCase();
    return message.contains('timeout') ||
        message.contains('timed out') ||
        message.contains('no internet') ||
        message.contains('network') ||
        message.contains('failed host lookup') ||
        message.contains('socket') ||
        message.contains('connection') ||
        message.contains('could not connect') ||
        message.contains('api probe failed');
  }

  Future<void> _markFarmSyncException(
    OfflineRepository repo,
    FarmRecord farm,
    ApiException error,
  ) async {
    final attempts = farm.syncAttempts + 1;
    if (_isTransientSyncError(error)) {
      await repo.markFarmPendingRetry(farm.localId, error.message, attempts);
      return;
    }
    await repo.markFarmFailed(farm.localId, error.message, attempts);
  }

  Future<void> _markPlotSyncException(
    OfflineRepository repo,
    PlotRecord plot,
    ApiException error,
  ) async {
    final attempts = plot.syncAttempts + 1;
    if (_isTransientSyncError(error)) {
      await repo.markPlotPendingRetry(plot.localId, error.message, attempts);
      return;
    }
    await repo.markPlotFailed(plot.localId, error.message, attempts);
  }

  Future<void> _markPlantingSyncException(
    OfflineRepository repo,
    PlantingRecord planting,
    ApiException error,
  ) async {
    final attempts = planting.syncAttempts + 1;
    if (_isTransientSyncError(error)) {
      await repo.markPlantingPendingRetry(planting.localId, error.message, attempts);
      return;
    }
    await repo.markPlantingFailed(planting.localId, error.message, attempts);
  }

  Future<void> _markSoilHealthSyncException(
    OfflineRepository repo,
    SoilHealthRecord soil,
    ApiException error,
  ) async {
    final attempts = soil.syncAttempts + 1;
    if (_isTransientSyncError(error)) {
      await repo.markSoilHealthPendingRetry(soil.localId, error.message, attempts);
      return;
    }
    await repo.markSoilHealthFailed(soil.localId, error.message, attempts);
  }

  Future<void> _pushFarms(OfflineRepository repo) async {
    final pending = await repo.listFarmsNeedingSync();
    for (final farm in pending) {
      if (farm.syncState == SyncState.conflict) continue;
      if (!repo.readyForRetry(farm.nextRetryAt)) continue;

      if (farm.deleted) {
        if (farm.serverId == null) {
          await repo.purgeFarmByLocalId(farm.localId);
          continue;
        }
        try {
          await ApiClient.deleteFarm(farm.serverId!);
          await repo.purgeFarmByLocalId(farm.localId);
        } on ApiUnauthorized {
          rethrow;
        } on ApiException catch (e) {
          await _markFarmSyncException(repo, farm, e);
        }
        continue;
      }

      if (farm.serverId == null) {
        try {
          final created = await ApiClient.createFarm(
            regionId: farm.regionId,
            farmName: farm.farmName,
            latitude: farm.latitude,
            longitude: farm.longitude,
            areaHectares: farm.areaHectares,
            farmType: farm.farmType,
            isActive: farm.isActive,
          );
          await repo.markFarmSynced(localId: farm.localId, server: created);
        } on ApiUnauthorized {
          rethrow;
        } on ApiException catch (e) {
          await _markFarmSyncException(repo, farm, e);
        }
        continue;
      }

      if (_missingServerVersion(farm.baseServerUpdatedAt, farm.serverUpdatedAt)) {
        await repo.markFarmFailed(
          farm.localId,
          'Missing server version. Refresh required before sync.',
          farm.syncAttempts + 1,
        );
        continue;
      }
      if (_hasConflict(farm.baseServerUpdatedAt, farm.serverUpdatedAt)) {
        await repo.markFarmConflict(
          farm.localId,
          'Farm changed on server. Review updates before syncing.',
        );
        continue;
      }

      try {
        final updated = await ApiClient.updateFarm(
          farmId: farm.serverId!,
          regionId: farm.regionId,
          farmName: farm.farmName,
          latitude: farm.latitude,
          longitude: farm.longitude,
          areaHectares: farm.areaHectares,
          farmType: farm.farmType,
          isActive: farm.isActive,
        );
        await repo.markFarmSynced(localId: farm.localId, server: updated);
      } on ApiUnauthorized {
        rethrow;
      } on ApiException catch (e) {
        await _markFarmSyncException(repo, farm, e);
      }
    }
  }

  Future<void> _pushPlots(OfflineRepository repo) async {
    final pending = await repo.listPlotsNeedingSync();
    for (final plot in pending) {
      if (plot.syncState == SyncState.conflict) continue;
      if (!repo.readyForRetry(plot.nextRetryAt)) continue;

      if (plot.deleted) {
        if (plot.serverId == null) {
          await repo.purgePlotByLocalId(plot.localId);
          continue;
        }
        try {
          await ApiClient.deletePlot(plot.serverId!);
          await repo.purgePlotByLocalId(plot.localId);
        } on ApiUnauthorized {
          rethrow;
        } on ApiException catch (e) {
          await _markPlotSyncException(repo, plot, e);
        }
        continue;
      }

      var farmServerId = plot.farmServerId;
      if (farmServerId == null && plot.farmLocalId != null) {
        final farm = await repo.getFarmByLocalId(plot.farmLocalId!);
        farmServerId = farm?.serverId;
      }

      if (plot.serverId == null) {
        if (farmServerId == null) {
          continue;
        }
        try {
          final created = await ApiClient.createPlot(
            farmId: farmServerId,
            plotName: plot.plotName,
            areaHectares: plot.areaHectares,
            soilType: plot.soilType,
            isActive: plot.isActive,
          );
          await repo.markPlotSynced(localId: plot.localId, server: created);
        } on ApiUnauthorized {
          rethrow;
        } on ApiException catch (e) {
          await _markPlotSyncException(repo, plot, e);
        }
        continue;
      }

      if (_missingServerVersion(plot.baseServerUpdatedAt, plot.serverUpdatedAt)) {
        await repo.markPlotFailed(
          plot.localId,
          'Missing server version. Refresh required before sync.',
          plot.syncAttempts + 1,
        );
        continue;
      }
      if (_hasConflict(plot.baseServerUpdatedAt, plot.serverUpdatedAt)) {
        await repo.markPlotConflict(
          plot.localId,
          'Plot changed on server. Review updates before syncing.',
        );
        continue;
      }

      try {
        final updated = await ApiClient.updatePlot(
          plotId: plot.serverId!,
          plotName: plot.plotName,
          areaHectares: plot.areaHectares,
          soilType: plot.soilType,
          isActive: plot.isActive,
        );
        await repo.markPlotSynced(localId: plot.localId, server: updated);
      } on ApiUnauthorized {
        rethrow;
      } on ApiException catch (e) {
        await _markPlotSyncException(repo, plot, e);
      }
    }
  }

  Future<void> _pushPlantings(OfflineRepository repo) async {
    final pending = await repo.listPlantingsNeedingSync();
    for (final planting in pending) {
      if (planting.syncState == SyncState.conflict) continue;
      if (!repo.readyForRetry(planting.nextRetryAt)) continue;

      if (planting.deleted) {
        if (planting.serverId == null) {
          await repo.purgePlantingByLocalId(planting.localId);
          continue;
        }
        try {
          await ApiClient.deletePlanting(planting.serverId!);
          await repo.purgePlantingByLocalId(planting.localId);
        } on ApiUnauthorized {
          rethrow;
        } on ApiException catch (e) {
          await _markPlantingSyncException(repo, planting, e);
        }
        continue;
      }

      var plotServerId = planting.plotServerId;
      if (plotServerId == null && planting.plotLocalId != null) {
        final plot = await repo.getPlotByLocalId(planting.plotLocalId!);
        plotServerId = plot?.serverId;
      }

      if (planting.serverId == null) {
        if (plotServerId == null) {
          await repo.markPlantingBlocked(
            planting.localId,
            'Waiting for the selected plot to finish syncing before this planting can upload.',
          );
          continue;
        }
        try {
          final created = await ApiClient.createPlanting(
            plotId: plotServerId,
            cropId: planting.cropId,
            plantingDate: planting.plantingDate,
            expectedHarvestDate: planting.expectedHarvestDate,
            status: planting.status,
            isActive: planting.isActive,
          );
          await repo.markPlantingSynced(localId: planting.localId, server: created);
        } on ApiUnauthorized {
          rethrow;
        } on ApiException catch (e) {
          await _markPlantingSyncException(repo, planting, e);
        }
        continue;
      }

      if (_missingServerVersion(planting.baseServerUpdatedAt, planting.serverUpdatedAt)) {
        await repo.markPlantingFailed(
          planting.localId,
          'Missing server version. Refresh required before sync.',
          planting.syncAttempts + 1,
        );
        continue;
      }
      if (_hasConflict(planting.baseServerUpdatedAt, planting.serverUpdatedAt)) {
        await repo.markPlantingConflict(
          planting.localId,
          'Planting changed on server. Review updates before syncing.',
        );
        continue;
      }

      try {
        final updated = await ApiClient.updatePlanting(
          plantingId: planting.serverId!,
          cropId: planting.cropId,
          plantingDate: planting.plantingDate,
          expectedHarvestDate: planting.expectedHarvestDate,
          status: planting.status,
          isActive: planting.isActive,
        );
        await repo.markPlantingSynced(localId: planting.localId, server: updated);
      } on ApiUnauthorized {
        rethrow;
      } on ApiException catch (e) {
        await _markPlantingSyncException(repo, planting, e);
      }
    }
  }

  Future<void> _pushSoilHealth(OfflineRepository repo) async {
    final pending = await repo.listSoilHealthNeedingSync();
    for (final soil in pending) {
      if (soil.syncState == SyncState.conflict) continue;
      if (!repo.readyForRetry(soil.nextRetryAt)) continue;

      if (soil.deleted) {
        if (soil.serverId == null) {
          await repo.purgeSoilHealthByLocalId(soil.localId);
          continue;
        }
        try {
          await ApiClient.deleteSoilHealth(soil.serverId!);
          await repo.purgeSoilHealthByLocalId(soil.localId);
        } on ApiUnauthorized {
          rethrow;
        } on ApiException catch (e) {
          await _markSoilHealthSyncException(repo, soil, e);
        }
        continue;
      }

      var plotServerId = soil.plotServerId;
      if (plotServerId == null && soil.plotLocalId != null) {
        final plot = await repo.getPlotByLocalId(soil.plotLocalId!);
        plotServerId = plot?.serverId;
      }

      if (soil.serverId == null) {
        if (plotServerId == null) {
          continue;
        }
        try {
          final created = await ApiClient.createSoilHealth(
            plotId: plotServerId,
            phLevel: soil.phLevel,
            nitrogen: soil.nitrogen,
            phosphorus: soil.phosphorus,
            potassium: soil.potassium,
            organicMatter: soil.organicMatter,
            moisture: soil.moistureLevel,
            soilType: soil.soilType,
            testMethod: soil.testMethod,
            dataSource: soil.dataSource,
            sensorDeviceId: soil.sensorDeviceId,
            sensorReadingId: soil.sensorReadingId,
            sensorPayload: soil.sensorPayload,
            fieldContext: soil.fieldContext,
            confidenceScore: soil.confidenceScore,
            testedAt: soil.testDate,
            evidencePath: soil.evidencePath,
          );
          await repo.markSoilHealthSynced(localId: soil.localId, server: created);
        } on ApiUnauthorized {
          rethrow;
        } on ApiException catch (e) {
          await _markSoilHealthSyncException(repo, soil, e);
        }
        continue;
      }

      if (_missingServerVersion(soil.baseServerUpdatedAt, soil.serverUpdatedAt)) {
        await repo.markSoilHealthFailed(
          soil.localId,
          'Missing server version. Refresh required before sync.',
          soil.syncAttempts + 1,
        );
        continue;
      }
      if (_hasConflict(soil.baseServerUpdatedAt, soil.serverUpdatedAt)) {
        await repo.markSoilHealthConflict(
          soil.localId,
          'Soil record changed on server. Review updates before syncing.',
        );
        continue;
      }

      try {
        final updated = await ApiClient.updateSoilHealth(
          soilHealthId: soil.serverId!,
          phLevel: soil.phLevel,
          nitrogen: soil.nitrogen,
          phosphorus: soil.phosphorus,
          potassium: soil.potassium,
          organicMatter: soil.organicMatter,
          moisture: soil.moistureLevel,
          soilType: soil.soilType,
          testMethod: soil.testMethod,
          dataSource: soil.dataSource,
          sensorDeviceId: soil.sensorDeviceId,
          sensorReadingId: soil.sensorReadingId,
          sensorPayload: soil.sensorPayload,
          fieldContext: soil.fieldContext,
          confidenceScore: soil.confidenceScore,
          testedAt: soil.testDate,
          reviewStatus: soil.reviewStatus,
          evidencePath: soil.evidencePath,
        );
        await repo.markSoilHealthSynced(localId: soil.localId, server: updated);
      } on ApiUnauthorized {
        rethrow;
      } on ApiException catch (e) {
        await _markSoilHealthSyncException(repo, soil, e);
      }
    }
  }
}
