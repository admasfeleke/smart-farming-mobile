import '../features/my_farm/models/planting_model.dart';
import 'sync_state.dart';

class FarmRecord {
  final int localId;
  final int? serverId;
  final int regionId;
  final String farmName;
  final double? latitude;
  final double? longitude;
  final double? areaHectares;
  final String? farmType;
  final bool isActive;
  final DateTime localUpdatedAt;
  final DateTime? serverCreatedAt;
  final DateTime? serverUpdatedAt;
  final DateTime? baseServerUpdatedAt;
  final SyncState syncState;
  final bool deleted;
  final String? conflictReason;
  final int syncAttempts;
  final DateTime? nextRetryAt;
  final String? syncError;

  const FarmRecord({
    required this.localId,
    required this.serverId,
    required this.regionId,
    required this.farmName,
    required this.latitude,
    required this.longitude,
    required this.areaHectares,
    required this.farmType,
    required this.isActive,
    required this.localUpdatedAt,
    required this.serverCreatedAt,
    required this.serverUpdatedAt,
    required this.baseServerUpdatedAt,
    required this.syncState,
    required this.deleted,
    required this.conflictReason,
    required this.syncAttempts,
    required this.nextRetryAt,
    required this.syncError,
  });

  int get id => localId;
  bool get isSynced => syncState == SyncState.synced && !deleted && serverId != null;

  FarmRecord copyWith({
    int? localId,
    int? serverId,
    int? regionId,
    String? farmName,
    double? latitude,
    double? longitude,
    double? areaHectares,
    String? farmType,
    bool? isActive,
    DateTime? localUpdatedAt,
    DateTime? serverCreatedAt,
    DateTime? serverUpdatedAt,
    DateTime? baseServerUpdatedAt,
    SyncState? syncState,
    bool? deleted,
    String? conflictReason,
    int? syncAttempts,
    DateTime? nextRetryAt,
    String? syncError,
  }) {
    return FarmRecord(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      regionId: regionId ?? this.regionId,
      farmName: farmName ?? this.farmName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      areaHectares: areaHectares ?? this.areaHectares,
      farmType: farmType ?? this.farmType,
      isActive: isActive ?? this.isActive,
      localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
      serverCreatedAt: serverCreatedAt ?? this.serverCreatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      baseServerUpdatedAt: baseServerUpdatedAt ?? this.baseServerUpdatedAt,
      syncState: syncState ?? this.syncState,
      deleted: deleted ?? this.deleted,
      conflictReason: conflictReason ?? this.conflictReason,
      syncAttempts: syncAttempts ?? this.syncAttempts,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      syncError: syncError ?? this.syncError,
    );
  }
}

class PlotRecord {
  final int localId;
  final int? serverId;
  final int? farmLocalId;
  final int? farmServerId;
  final String plotName;
  final double? areaHectares;
  final String soilType;
  final bool isActive;
  final DateTime localUpdatedAt;
  final DateTime? serverCreatedAt;
  final DateTime? serverUpdatedAt;
  final DateTime? baseServerUpdatedAt;
  final SyncState syncState;
  final bool deleted;
  final String? conflictReason;
  final int syncAttempts;
  final DateTime? nextRetryAt;
  final String? syncError;

  const PlotRecord({
    required this.localId,
    required this.serverId,
    required this.farmLocalId,
    required this.farmServerId,
    required this.plotName,
    required this.areaHectares,
    required this.soilType,
    required this.isActive,
    required this.localUpdatedAt,
    required this.serverCreatedAt,
    required this.serverUpdatedAt,
    required this.baseServerUpdatedAt,
    required this.syncState,
    required this.deleted,
    required this.conflictReason,
    required this.syncAttempts,
    required this.nextRetryAt,
    required this.syncError,
  });

  int get id => localId;
  bool get isSynced => syncState == SyncState.synced && !deleted && serverId != null;

  PlotRecord copyWith({
    int? localId,
    int? serverId,
    int? farmLocalId,
    int? farmServerId,
    String? plotName,
    double? areaHectares,
    String? soilType,
    bool? isActive,
    DateTime? localUpdatedAt,
    DateTime? serverCreatedAt,
    DateTime? serverUpdatedAt,
    DateTime? baseServerUpdatedAt,
    SyncState? syncState,
    bool? deleted,
    String? conflictReason,
    int? syncAttempts,
    DateTime? nextRetryAt,
    String? syncError,
  }) {
    return PlotRecord(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      farmLocalId: farmLocalId ?? this.farmLocalId,
      farmServerId: farmServerId ?? this.farmServerId,
      plotName: plotName ?? this.plotName,
      areaHectares: areaHectares ?? this.areaHectares,
      soilType: soilType ?? this.soilType,
      isActive: isActive ?? this.isActive,
      localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
      serverCreatedAt: serverCreatedAt ?? this.serverCreatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      baseServerUpdatedAt: baseServerUpdatedAt ?? this.baseServerUpdatedAt,
      syncState: syncState ?? this.syncState,
      deleted: deleted ?? this.deleted,
      conflictReason: conflictReason ?? this.conflictReason,
      syncAttempts: syncAttempts ?? this.syncAttempts,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      syncError: syncError ?? this.syncError,
    );
  }
}

class PlantingRecord {
  final int localId;
  final int? serverId;
  final int? plotLocalId;
  final int? plotServerId;
  final int cropId;
  final DateTime plantingDate;
  final DateTime? expectedHarvestDate;
  final String status;
  final bool isActive;
  final DateTime localUpdatedAt;
  final DateTime? serverCreatedAt;
  final DateTime? serverUpdatedAt;
  final DateTime? baseServerUpdatedAt;
  final SyncState syncState;
  final bool deleted;
  final String? conflictReason;
  final int syncAttempts;
  final DateTime? nextRetryAt;
  final String? syncError;

  const PlantingRecord({
    required this.localId,
    required this.serverId,
    required this.plotLocalId,
    required this.plotServerId,
    required this.cropId,
    required this.plantingDate,
    required this.expectedHarvestDate,
    required this.status,
    required this.isActive,
    required this.localUpdatedAt,
    required this.serverCreatedAt,
    required this.serverUpdatedAt,
    required this.baseServerUpdatedAt,
    required this.syncState,
    required this.deleted,
    required this.conflictReason,
    required this.syncAttempts,
    required this.nextRetryAt,
    required this.syncError,
  });

  int get id => localId;
  bool get isSynced => syncState == SyncState.synced && !deleted && serverId != null;

  PlantingRecord copyWith({
    int? localId,
    int? serverId,
    int? plotLocalId,
    int? plotServerId,
    int? cropId,
    DateTime? plantingDate,
    DateTime? expectedHarvestDate,
    String? status,
    bool? isActive,
    DateTime? localUpdatedAt,
    DateTime? serverCreatedAt,
    DateTime? serverUpdatedAt,
    DateTime? baseServerUpdatedAt,
    SyncState? syncState,
    bool? deleted,
    String? conflictReason,
    int? syncAttempts,
    DateTime? nextRetryAt,
    String? syncError,
  }) {
    return PlantingRecord(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      plotLocalId: plotLocalId ?? this.plotLocalId,
      plotServerId: plotServerId ?? this.plotServerId,
      cropId: cropId ?? this.cropId,
      plantingDate: plantingDate ?? this.plantingDate,
      expectedHarvestDate: expectedHarvestDate ?? this.expectedHarvestDate,
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
      localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
      serverCreatedAt: serverCreatedAt ?? this.serverCreatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      baseServerUpdatedAt: baseServerUpdatedAt ?? this.baseServerUpdatedAt,
      syncState: syncState ?? this.syncState,
      deleted: deleted ?? this.deleted,
      conflictReason: conflictReason ?? this.conflictReason,
      syncAttempts: syncAttempts ?? this.syncAttempts,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      syncError: syncError ?? this.syncError,
    );
  }

  PlantingModel toPlantingModel({bool useServerId = true}) {
    return PlantingModel(
      id: useServerId ? (serverId ?? localId) : localId,
      plotId: useServerId ? (plotServerId ?? plotLocalId ?? 0) : (plotLocalId ?? 0),
      cropId: cropId,
      plantingDate: plantingDate,
      expectedHarvestDate: expectedHarvestDate,
      status: status,
      isActive: isActive,
      createdAt: serverCreatedAt ?? localUpdatedAt,
      updatedAt: serverUpdatedAt ?? localUpdatedAt,
    );
  }
}

class SoilHealthRecord {
  final int localId;
  final int? serverId;
  final int? plotLocalId;
  final int? plotServerId;
  final double? phLevel;
  final double? nitrogen;
  final double? phosphorus;
  final double? potassium;
  final double? organicMatter;
  final double? moistureLevel;
  final String? soilType;
  final DateTime? testDate;
  final String? testMethod;
  final String? reviewStatus;
  final int? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewReasonCode;
  final String? reviewComment;
  final String? evidencePath;
  final String? evidenceUrl;
  final DateTime localUpdatedAt;
  final DateTime? serverCreatedAt;
  final DateTime? serverUpdatedAt;
  final DateTime? baseServerUpdatedAt;
  final SyncState syncState;
  final bool deleted;
  final String? conflictReason;
  final int syncAttempts;
  final DateTime? nextRetryAt;
  final String? syncError;

  const SoilHealthRecord({
    required this.localId,
    required this.serverId,
    required this.plotLocalId,
    required this.plotServerId,
    required this.phLevel,
    required this.nitrogen,
    required this.phosphorus,
    required this.potassium,
    required this.organicMatter,
    required this.moistureLevel,
    required this.soilType,
    required this.testDate,
    required this.testMethod,
    required this.reviewStatus,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.reviewReasonCode,
    required this.reviewComment,
    required this.evidencePath,
    required this.evidenceUrl,
    required this.localUpdatedAt,
    required this.serverCreatedAt,
    required this.serverUpdatedAt,
    required this.baseServerUpdatedAt,
    required this.syncState,
    required this.deleted,
    required this.conflictReason,
    required this.syncAttempts,
    required this.nextRetryAt,
    required this.syncError,
  });

  int get id => localId;
  bool get isSynced => syncState == SyncState.synced && !deleted && serverId != null;

  SoilHealthRecord copyWith({
    int? localId,
    int? serverId,
    int? plotLocalId,
    int? plotServerId,
    double? phLevel,
    double? nitrogen,
    double? phosphorus,
    double? potassium,
    double? organicMatter,
    double? moistureLevel,
    String? soilType,
    DateTime? testDate,
    String? testMethod,
    String? reviewStatus,
    int? reviewedBy,
    DateTime? reviewedAt,
    String? reviewReasonCode,
    String? reviewComment,
    String? evidencePath,
    String? evidenceUrl,
    DateTime? localUpdatedAt,
    DateTime? serverCreatedAt,
    DateTime? serverUpdatedAt,
    DateTime? baseServerUpdatedAt,
    SyncState? syncState,
    bool? deleted,
    String? conflictReason,
    int? syncAttempts,
    DateTime? nextRetryAt,
    String? syncError,
  }) {
    return SoilHealthRecord(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      plotLocalId: plotLocalId ?? this.plotLocalId,
      plotServerId: plotServerId ?? this.plotServerId,
      phLevel: phLevel ?? this.phLevel,
      nitrogen: nitrogen ?? this.nitrogen,
      phosphorus: phosphorus ?? this.phosphorus,
      potassium: potassium ?? this.potassium,
      organicMatter: organicMatter ?? this.organicMatter,
      moistureLevel: moistureLevel ?? this.moistureLevel,
      soilType: soilType ?? this.soilType,
      testDate: testDate ?? this.testDate,
      testMethod: testMethod ?? this.testMethod,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewReasonCode: reviewReasonCode ?? this.reviewReasonCode,
      reviewComment: reviewComment ?? this.reviewComment,
      evidencePath: evidencePath ?? this.evidencePath,
      evidenceUrl: evidenceUrl ?? this.evidenceUrl,
      localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
      serverCreatedAt: serverCreatedAt ?? this.serverCreatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      baseServerUpdatedAt: baseServerUpdatedAt ?? this.baseServerUpdatedAt,
      syncState: syncState ?? this.syncState,
      deleted: deleted ?? this.deleted,
      conflictReason: conflictReason ?? this.conflictReason,
      syncAttempts: syncAttempts ?? this.syncAttempts,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      syncError: syncError ?? this.syncError,
    );
  }
}
