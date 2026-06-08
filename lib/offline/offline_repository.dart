import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../features/my_farm/models/farm_model.dart';
import '../features/my_farm/models/plot_model.dart';
import '../features/my_farm/models/planting_model.dart';
import '../language_store.dart';
import '../localization.dart';
import 'local_db.dart';
import 'offline_models.dart';
import 'sync_state.dart';

class OfflineSyncSummary {
  final int pendingCount;
  final int failedCount;
  final int conflictCount;
  final int deletedCount;

  const OfflineSyncSummary({
    required this.pendingCount,
    required this.failedCount,
    required this.conflictCount,
    required this.deletedCount,
  });

  int get actionableCount => pendingCount + failedCount + deletedCount;
  int get totalIssues => actionableCount + conflictCount;
}

class OfflineSyncEntitySummary {
  final String entityKey;
  final int pendingCount;
  final int failedCount;
  final int conflictCount;
  final int deletedCount;

  const OfflineSyncEntitySummary({
    required this.entityKey,
    required this.pendingCount,
    required this.failedCount,
    required this.conflictCount,
    required this.deletedCount,
  });

  int get totalIssues => pendingCount + failedCount + conflictCount + deletedCount;
}

class OfflineConflictItem {
  final String entityKey;
  final int localId;
  final int? serverId;
  final String title;
  final String? details;
  final String? conflictReason;
  final String? syncError;
  final DateTime? localUpdatedAt;

  const OfflineConflictItem({
    required this.entityKey,
    required this.localId,
    required this.serverId,
    required this.title,
    required this.details,
    required this.conflictReason,
    required this.syncError,
    required this.localUpdatedAt,
  });
}

class OfflineRepository {
  OfflineRepository._();

  static final OfflineRepository instance = OfflineRepository._();

  static const Duration _initialRetryDelay = Duration(minutes: 1);
  static const Duration _maxRetryDelay = Duration(hours: 12);

  Future<Database> _db() => LocalDb.instance.database();

  int _toInt(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int? _toNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  double? _toDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Map<String, dynamic>? _jsonMapOrNull(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is! String || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _jsonOrNull(Map<String, dynamic>? value) {
    if (value == null || value.isEmpty) return null;
    return jsonEncode(value);
  }

  bool _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' || normalized == 'true' || normalized == 'yes';
    }
    return false;
  }

  DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  String? _dateOrNull(DateTime? value) => value?.toUtc().toIso8601String();

  DateTime _nowUtc() => DateTime.now().toUtc();

  String _generateClientId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = math.Random().nextInt(1 << 31);
    return 'local_${now}_$rand';
  }

  DateTime _nextRetryAt(int attempts) {
    final boundedAttempts = attempts < 1 ? 1 : attempts;
    final multiplier = math.pow(2, boundedAttempts - 1).toInt();
    final seconds = _initialRetryDelay.inSeconds * multiplier;
    final boundedSeconds = seconds > _maxRetryDelay.inSeconds
        ? _maxRetryDelay.inSeconds
        : seconds;
    return _nowUtc().add(Duration(seconds: boundedSeconds));
  }

  Future<OfflineSyncSummary> getSyncSummary() async {
    final db = await _db();
    await _normalizeTransientFailures(db);
    final summaries = await Future.wait<OfflineSyncSummary>(<Future<OfflineSyncSummary>>[
      _syncSummaryForTable(db, 'farms'),
      _syncSummaryForTable(db, 'plots'),
      _syncSummaryForTable(db, 'plantings'),
      _syncSummaryForTable(db, 'soil_health'),
    ]);

    return OfflineSyncSummary(
      pendingCount: summaries.fold<int>(0, (sum, item) => sum + item.pendingCount),
      failedCount: summaries.fold<int>(0, (sum, item) => sum + item.failedCount),
      conflictCount: summaries.fold<int>(0, (sum, item) => sum + item.conflictCount),
      deletedCount: summaries.fold<int>(0, (sum, item) => sum + item.deletedCount),
    );
  }

  Future<List<OfflineSyncEntitySummary>> getSyncSummaryByEntity() async {
    final db = await _db();
    await _normalizeTransientFailures(db);
    final config = <Map<String, String>>[
      <String, String>{'table': 'farms', 'key': 'farms'},
      <String, String>{'table': 'plots', 'key': 'plots'},
      <String, String>{'table': 'plantings', 'key': 'plantings'},
      <String, String>{'table': 'soil_health', 'key': 'soil_health'},
    ];

    final summaries = <OfflineSyncEntitySummary>[];
    for (final item in config) {
      final summary = await _syncSummaryForTable(db, item['table']!);
      summaries.add(
        OfflineSyncEntitySummary(
          entityKey: item['key']!,
          pendingCount: summary.pendingCount,
          failedCount: summary.failedCount,
          conflictCount: summary.conflictCount,
          deletedCount: summary.deletedCount,
        ),
      );
    }
    return summaries;
  }

  Future<List<OfflineConflictItem>> getConflictItems() async {
    final db = await _db();
    final items = <OfflineConflictItem>[
      ...await _conflictItemsForNamedTable(
        db,
        table: 'farms',
        entityKey: 'farms',
        titleColumn: 'farm_name',
      ),
      ...await _conflictItemsForNamedTable(
        db,
        table: 'plots',
        entityKey: 'plots',
        titleColumn: 'plot_name',
      ),
      ...await _conflictItemsForPlantings(db),
      ...await _conflictItemsForSoilHealth(db),
    ];

    items.sort((a, b) {
      final aTime = a.localUpdatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.localUpdatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return items;
  }

  Future<OfflineSyncSummary> _syncSummaryForTable(Database db, String table) async {
    final rows = await db.rawQuery('''
      SELECT
        SUM(CASE WHEN sync_state = 'pending' AND deleted = 0 THEN 1 ELSE 0 END) AS pending_count,
        SUM(CASE WHEN sync_state = 'failed' AND deleted = 0 THEN 1 ELSE 0 END) AS failed_count,
        SUM(CASE WHEN sync_state = 'conflict' AND deleted = 0 THEN 1 ELSE 0 END) AS conflict_count,
        SUM(CASE WHEN deleted = 1 THEN 1 ELSE 0 END) AS deleted_count
      FROM $table
    ''');
    final row = rows.isEmpty ? const <String, Object?>{} : rows.first;
    return OfflineSyncSummary(
      pendingCount: _toInt(row['pending_count']),
      failedCount: _toInt(row['failed_count']),
      conflictCount: _toInt(row['conflict_count']),
      deletedCount: _toInt(row['deleted_count']),
    );
  }

  Future<void> _normalizeTransientFailures(Database db) async {
    for (final table in const ['farms', 'plots', 'plantings', 'soil_health']) {
      await db.update(
        table,
        <String, Object?>{
          'sync_state': syncStateToString(SyncState.pending),
        },
        where: '''
          sync_state = 'failed'
          AND deleted = 0
          AND sync_error IS NOT NULL
          AND (
            lower(sync_error) LIKE '%timeout%'
            OR lower(sync_error) LIKE '%timed out%'
            OR lower(sync_error) LIKE '%no internet%'
            OR lower(sync_error) LIKE '%network%'
            OR lower(sync_error) LIKE '%failed host lookup%'
            OR lower(sync_error) LIKE '%socket%'
            OR lower(sync_error) LIKE '%connection%'
            OR lower(sync_error) LIKE '%could not connect%'
            OR lower(sync_error) LIKE '%api probe failed%'
          )
        ''',
      );
    }
  }

  Future<List<OfflineConflictItem>> _conflictItemsForNamedTable(
    Database db, {
    required String table,
    required String entityKey,
    required String titleColumn,
  }) async {
    final rows = await db.query(
      table,
      columns: <String>[
        'local_id',
        'server_id',
        titleColumn,
        'local_updated_at',
        'conflict_reason',
        'sync_error',
      ],
      where: 'sync_state = ?',
      whereArgs: <Object?>['conflict'],
      orderBy: 'local_updated_at DESC',
    );
    return rows
        .map(
          (row) => OfflineConflictItem(
            entityKey: entityKey,
            localId: _toInt(row['local_id']),
            serverId: _toNullableInt(row['server_id']),
            title: row[titleColumn]?.toString().trim().isNotEmpty == true
                ? row[titleColumn]!.toString().trim()
                : '$entityKey #${_toInt(row['local_id'])}',
            details: null,
            conflictReason: row['conflict_reason']?.toString(),
            syncError: row['sync_error']?.toString(),
            localUpdatedAt: _parseDate(row['local_updated_at']),
          ),
        )
        .toList();
  }

  Future<List<OfflineConflictItem>> _conflictItemsForPlantings(Database db) async {
    final rows = await db.query(
      'plantings',
      columns: <String>[
        'local_id',
        'server_id',
        'crop_id',
        'planting_date',
        'status',
        'local_updated_at',
        'conflict_reason',
        'sync_error',
      ],
      where: 'sync_state = ?',
      whereArgs: <Object?>['conflict'],
      orderBy: 'local_updated_at DESC',
    );
    return rows.map((row) {
      final cropId = _toInt(row['crop_id']);
      final plantingDate = _parseDate(row['planting_date']);
      final status = row['status']?.toString().trim() ?? '';
      final detailParts = <String>[
        if (plantingDate != null) _shortDate(plantingDate),
        if (status.isNotEmpty) status,
      ];
      return OfflineConflictItem(
        entityKey: 'plantings',
        localId: _toInt(row['local_id']),
        serverId: _toNullableInt(row['server_id']),
        title: 'Crop #$cropId',
        details: detailParts.isEmpty ? null : detailParts.join(' • '),
        conflictReason: row['conflict_reason']?.toString(),
        syncError: row['sync_error']?.toString(),
        localUpdatedAt: _parseDate(row['local_updated_at']),
      );
    }).toList();
  }

  Future<List<OfflineConflictItem>> _conflictItemsForSoilHealth(Database db) async {
    final rows = await db.query(
      'soil_health',
      columns: <String>[
        'local_id',
        'server_id',
        'plot_local_id',
        'plot_server_id',
        'soil_type',
        'test_date',
        'local_updated_at',
        'conflict_reason',
        'sync_error',
      ],
      where: 'sync_state = ?',
      whereArgs: <Object?>['conflict'],
      orderBy: 'local_updated_at DESC',
    );
    return rows.map((row) {
      final testDate = _parseDate(row['test_date']);
      final plotLocalId = _toNullableInt(row['plot_local_id']);
      final plotServerId = _toNullableInt(row['plot_server_id']);
      final soilType = row['soil_type']?.toString().trim() ?? '';
      final lang = LanguageStore.notifier.value;
      final plotLabel = plotLocalId != null
          ? L.t(lang, 'plot_number', params: {'value': '$plotLocalId'})
          : plotServerId != null
              ? L.t(lang, 'server_plot_number', params: {'value': '$plotServerId'})
              : null;
      final detailParts = <String>[
        ?plotLabel,
        if (soilType.isNotEmpty) soilType,
      ];
      return OfflineConflictItem(
        entityKey: 'soil_health',
        localId: _toInt(row['local_id']),
        serverId: _toNullableInt(row['server_id']),
        title: testDate == null
            ? L.t(lang, 'soil_record')
            : L.t(lang, 'soil_test_date', params: {'date': _shortDate(testDate)}),
        details: detailParts.isEmpty ? null : detailParts.join(' • '),
        conflictReason: row['conflict_reason']?.toString(),
        syncError: row['sync_error']?.toString(),
        localUpdatedAt: _parseDate(row['local_updated_at']),
      );
    }).toList();
  }

  String _shortDate(DateTime value) => value.toUtc().toIso8601String().split('T').first;

  FarmRecord _farmFromRow(Map<String, Object?> row) {
    return FarmRecord(
      localId: _toInt(row['local_id']),
      serverId: _toNullableInt(row['server_id']),
      regionId: _toInt(row['region_id']),
      farmName: row['farm_name']?.toString() ?? '',
      latitude: _toDouble(row['latitude']),
      longitude: _toDouble(row['longitude']),
      areaHectares: _toDouble(row['area_hectares']),
      farmType: row['farm_type']?.toString(),
      isActive: _toBool(row['is_active']),
      localUpdatedAt:
          _parseDate(row['local_updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      serverCreatedAt: _parseDate(row['server_created_at']),
      serverUpdatedAt: _parseDate(row['server_updated_at']),
      baseServerUpdatedAt: _parseDate(row['base_server_updated_at']),
      syncState: syncStateFromString(row['sync_state']?.toString()),
      deleted: _toBool(row['deleted']),
      conflictReason: row['conflict_reason']?.toString(),
      syncAttempts: _toInt(row['sync_attempts']),
      nextRetryAt: _parseDate(row['sync_next_retry_at']),
      syncError: row['sync_error']?.toString(),
    );
  }

  PlotRecord _plotFromRow(Map<String, Object?> row) {
    return PlotRecord(
      localId: _toInt(row['local_id']),
      serverId: _toNullableInt(row['server_id']),
      farmLocalId: _toNullableInt(row['farm_local_id']),
      farmServerId: _toNullableInt(row['farm_server_id']),
      plotName: row['plot_name']?.toString() ?? '',
      areaHectares: _toDouble(row['area_hectares']),
      soilType: row['soil_type']?.toString() ?? '',
      isActive: _toBool(row['is_active']),
      localUpdatedAt:
          _parseDate(row['local_updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      serverCreatedAt: _parseDate(row['server_created_at']),
      serverUpdatedAt: _parseDate(row['server_updated_at']),
      baseServerUpdatedAt: _parseDate(row['base_server_updated_at']),
      syncState: syncStateFromString(row['sync_state']?.toString()),
      deleted: _toBool(row['deleted']),
      conflictReason: row['conflict_reason']?.toString(),
      syncAttempts: _toInt(row['sync_attempts']),
      nextRetryAt: _parseDate(row['sync_next_retry_at']),
      syncError: row['sync_error']?.toString(),
    );
  }

  PlantingRecord _plantingFromRow(Map<String, Object?> row) {
    return PlantingRecord(
      localId: _toInt(row['local_id']),
      serverId: _toNullableInt(row['server_id']),
      plotLocalId: _toNullableInt(row['plot_local_id']),
      plotServerId: _toNullableInt(row['plot_server_id']),
      cropId: _toInt(row['crop_id']),
      plantingDate:
          _parseDate(row['planting_date']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      expectedHarvestDate: _parseDate(row['expected_harvest_date']),
      status: row['status']?.toString() ?? '',
      isActive: _toBool(row['is_active']),
      localUpdatedAt:
          _parseDate(row['local_updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      serverCreatedAt: _parseDate(row['server_created_at']),
      serverUpdatedAt: _parseDate(row['server_updated_at']),
      baseServerUpdatedAt: _parseDate(row['base_server_updated_at']),
      syncState: syncStateFromString(row['sync_state']?.toString()),
      deleted: _toBool(row['deleted']),
      conflictReason: row['conflict_reason']?.toString(),
      syncAttempts: _toInt(row['sync_attempts']),
      nextRetryAt: _parseDate(row['sync_next_retry_at']),
      syncError: row['sync_error']?.toString(),
    );
  }

  SoilHealthRecord _soilFromRow(Map<String, Object?> row) {
    return SoilHealthRecord(
      localId: _toInt(row['local_id']),
      serverId: _toNullableInt(row['server_id']),
      plotLocalId: _toNullableInt(row['plot_local_id']),
      plotServerId: _toNullableInt(row['plot_server_id']),
      phLevel: _toDouble(row['ph_level']),
      nitrogen: _toDouble(row['nitrogen']),
      phosphorus: _toDouble(row['phosphorus']),
      potassium: _toDouble(row['potassium']),
      organicMatter: _toDouble(row['organic_matter']),
      moistureLevel: _toDouble(row['moisture_level']),
      soilType: row['soil_type']?.toString(),
      testDate: _parseDate(row['test_date']),
      testMethod: row['test_method']?.toString(),
      dataSource: row['data_source']?.toString(),
      sensorDeviceId: row['sensor_device_id']?.toString(),
      sensorReadingId: row['sensor_reading_id']?.toString(),
      sensorPayload: _jsonMapOrNull(row['sensor_payload']),
      fieldContext: _jsonMapOrNull(row['field_context']),
      confidenceScore: _toDouble(row['confidence_score']),
      reviewStatus: row['review_status']?.toString(),
      reviewedBy: _toNullableInt(row['reviewed_by']),
      reviewedAt: _parseDate(row['reviewed_at']),
      reviewReasonCode: row['review_reason_code']?.toString(),
      reviewComment: row['review_comment']?.toString(),
      evidencePath: row['evidence_path']?.toString(),
      evidenceUrl: row['evidence_url']?.toString(),
      localUpdatedAt:
          _parseDate(row['local_updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      serverCreatedAt: _parseDate(row['server_created_at']),
      serverUpdatedAt: _parseDate(row['server_updated_at']),
      baseServerUpdatedAt: _parseDate(row['base_server_updated_at']),
      syncState: syncStateFromString(row['sync_state']?.toString()),
      deleted: _toBool(row['deleted']),
      conflictReason: row['conflict_reason']?.toString(),
      syncAttempts: _toInt(row['sync_attempts']),
      nextRetryAt: _parseDate(row['sync_next_retry_at']),
      syncError: row['sync_error']?.toString(),
    );
  }

  Future<List<FarmRecord>> listFarms({bool includeDeleted = false}) async {
    final db = await _db();
    final rows = await db.query(
      'farms',
      where: includeDeleted ? null : 'deleted = 0',
      orderBy: 'farm_name ASC',
    );
    return rows.map(_farmFromRow).toList();
  }

  Future<Map<int, int>> plotCountsByFarm() async {
    final db = await _db();
    final rows = await db.rawQuery(
      'SELECT farm_local_id, COUNT(*) as count FROM plots WHERE deleted = 0 GROUP BY farm_local_id',
    );
    final counts = <int, int>{};
    for (final row in rows) {
      final farmLocalId = _toNullableInt(row['farm_local_id']);
      if (farmLocalId == null) continue;
      counts[farmLocalId] = _toInt(row['count'], 0);
    }
    return counts;
  }

  Future<List<PlotRecord>> listPlotsByFarmLocalId(int farmLocalId) async {
    final db = await _db();
    final rows = await db.query(
      'plots',
      where: 'farm_local_id = ? AND deleted = 0',
      whereArgs: <Object?>[farmLocalId],
      orderBy: 'plot_name ASC',
    );
    return rows.map(_plotFromRow).toList();
  }

  Future<List<PlotRecord>> listPlotsByFarmServerId(int farmServerId) async {
    final db = await _db();
    final rows = await db.query(
      'plots',
      where: 'farm_server_id = ? AND deleted = 0',
      whereArgs: <Object?>[farmServerId],
      orderBy: 'plot_name ASC',
    );
    return rows.map(_plotFromRow).toList();
  }

  Future<List<PlantingRecord>> listPlantingsByPlotLocalId(int plotLocalId) async {
    final db = await _db();
    final rows = await db.query(
      'plantings',
      where: 'plot_local_id = ? AND deleted = 0',
      whereArgs: <Object?>[plotLocalId],
      orderBy: 'planting_date DESC',
    );
    return rows.map(_plantingFromRow).toList();
  }

  Future<List<PlantingRecord>> listPlantingsByPlotServerId(int plotServerId) async {
    final db = await _db();
    final rows = await db.query(
      'plantings',
      where: 'plot_server_id = ? AND deleted = 0',
      whereArgs: <Object?>[plotServerId],
      orderBy: 'planting_date DESC',
    );
    return rows.map(_plantingFromRow).toList();
  }

  Future<List<SoilHealthRecord>> listSoilHealth({int? plotLocalId}) async {
    final db = await _db();
    final rows = await db.query(
      'soil_health',
      where: plotLocalId == null ? 'deleted = 0' : 'plot_local_id = ? AND deleted = 0',
      whereArgs: plotLocalId == null ? null : <Object?>[plotLocalId],
      orderBy: 'test_date DESC',
    );
    return rows.map(_soilFromRow).toList();
  }

  Future<List<SoilHealthRecord>> listSoilHealthByPlotServerId(int plotServerId) async {
    final db = await _db();
    final rows = await db.query(
      'soil_health',
      where: 'plot_server_id = ? AND deleted = 0',
      whereArgs: <Object?>[plotServerId],
      orderBy: 'test_date DESC',
    );
    return rows.map(_soilFromRow).toList();
  }

  Future<FarmRecord?> getFarmByLocalId(int localId) async {
    final db = await _db();
    final rows = await db.query('farms', where: 'local_id = ?', whereArgs: [localId]);
    if (rows.isEmpty) return null;
    return _farmFromRow(rows.first);
  }

  Future<FarmRecord?> getFarmByServerId(int serverId) async {
    final db = await _db();
    final rows = await db.query('farms', where: 'server_id = ?', whereArgs: [serverId]);
    if (rows.isEmpty) return null;
    return _farmFromRow(rows.first);
  }

  Future<PlotRecord?> getPlotByLocalId(int localId) async {
    final db = await _db();
    final rows = await db.query('plots', where: 'local_id = ?', whereArgs: [localId]);
    if (rows.isEmpty) return null;
    return _plotFromRow(rows.first);
  }

  Future<PlotRecord?> getPlotByServerId(int serverId) async {
    final db = await _db();
    final rows = await db.query('plots', where: 'server_id = ?', whereArgs: [serverId]);
    if (rows.isEmpty) return null;
    return _plotFromRow(rows.first);
  }

  Future<PlantingRecord?> getPlantingByLocalId(int localId) async {
    final db = await _db();
    final rows = await db.query('plantings', where: 'local_id = ?', whereArgs: [localId]);
    if (rows.isEmpty) return null;
    return _plantingFromRow(rows.first);
  }

  Future<PlantingRecord?> getPlantingByServerId(int serverId) async {
    final db = await _db();
    final rows =
        await db.query('plantings', where: 'server_id = ?', whereArgs: [serverId]);
    if (rows.isEmpty) return null;
    return _plantingFromRow(rows.first);
  }

  Future<SoilHealthRecord?> getSoilHealthByLocalId(int localId) async {
    final db = await _db();
    final rows =
        await db.query('soil_health', where: 'local_id = ?', whereArgs: [localId]);
    if (rows.isEmpty) return null;
    return _soilFromRow(rows.first);
  }

  Future<SoilHealthRecord?> getSoilHealthByServerId(int serverId) async {
    final db = await _db();
    final rows =
        await db.query('soil_health', where: 'server_id = ?', whereArgs: [serverId]);
    if (rows.isEmpty) return null;
    return _soilFromRow(rows.first);
  }

  Future<FarmRecord> createFarmLocal({
    required int regionId,
    required String farmName,
    double? latitude,
    double? longitude,
    double? areaHectares,
    String? farmType,
    bool isActive = true,
  }) async {
    final db = await _db();
    final now = _nowUtc();
    final localId = await db.insert(
      'farms',
      <String, Object?>{
        'client_id': _generateClientId(),
        'region_id': regionId,
        'farm_name': farmName,
        'latitude': latitude,
        'longitude': longitude,
        'area_hectares': areaHectares,
        'farm_type': farmType,
        'is_active': isActive ? 1 : 0,
        'local_updated_at': _dateOrNull(now),
        'sync_state': syncStateToString(SyncState.pending),
        'deleted': 0,
        'sync_attempts': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return (await getFarmByLocalId(localId))!;
  }

  Future<void> updateFarmLocal({
    required int localId,
    int? regionId,
    String? farmName,
    double? latitude,
    double? longitude,
    double? areaHectares,
    String? farmType,
    bool? isActive,
  }) async {
    final existing = await getFarmByLocalId(localId);
    if (existing == null) return;
    final now = _nowUtc();
    final baseServer =
        existing.baseServerUpdatedAt ?? (existing.syncState == SyncState.synced
            ? existing.serverUpdatedAt
            : existing.baseServerUpdatedAt);
    final nextSyncState =
        existing.syncState == SyncState.synced ? SyncState.pending : existing.syncState;

    final db = await _db();
    await db.update(
      'farms',
      <String, Object?>{
        'region_id': regionId ?? existing.regionId,
        'farm_name': farmName ?? existing.farmName,
        'latitude': latitude ?? existing.latitude,
        'longitude': longitude ?? existing.longitude,
        'area_hectares': areaHectares ?? existing.areaHectares,
        'farm_type': farmType ?? existing.farmType,
        'is_active': (isActive ?? existing.isActive) ? 1 : 0,
        'local_updated_at': _dateOrNull(now),
        'sync_state': syncStateToString(nextSyncState),
        'base_server_updated_at': _dateOrNull(baseServer),
        'sync_attempts': 0,
        'sync_next_retry_at': null,
        'sync_error': null,
        'conflict_reason': null,
        'deleted': 0,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> deleteFarmLocal(int localId) async {
    final existing = await getFarmByLocalId(localId);
    if (existing == null) return;
    final db = await _db();
    final now = _nowUtc();
    final plotRows = await db.query(
      'plots',
      columns: ['local_id'],
      where: 'farm_local_id = ?',
      whereArgs: [localId],
    );
    final plotIds =
        plotRows.map((row) => _toNullableInt(row['local_id'])).whereType<int>().toList();
    if (plotIds.isNotEmpty) {
      final placeholders = List.filled(plotIds.length, '?').join(',');
      await db.delete(
        'plantings',
        where: 'plot_local_id IN ($placeholders)',
        whereArgs: plotIds,
      );
      await db.delete(
        'soil_health',
        where: 'plot_local_id IN ($placeholders)',
        whereArgs: plotIds,
      );
    }
    await db.delete('plots', where: 'farm_local_id = ?', whereArgs: [localId]);

    if (existing.serverId == null) {
      await db.delete('farms', where: 'local_id = ?', whereArgs: [localId]);
      return;
    }

    await db.update(
      'farms',
      <String, Object?>{
        'deleted': 1,
        'sync_state': syncStateToString(SyncState.pending),
        'local_updated_at': _dateOrNull(now),
        'sync_attempts': 0,
        'sync_next_retry_at': null,
        'sync_error': null,
        'conflict_reason': null,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> purgeFarmByLocalId(int localId) async {
    final db = await _db();
    await db.delete('farms', where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<PlotRecord> createPlotLocal({
    required int farmLocalId,
    required String plotName,
    double? areaHectares,
    String? soilType,
    bool isActive = true,
  }) async {
    final db = await _db();
    final now = _nowUtc();
    final farm = await getFarmByLocalId(farmLocalId);
    final localId = await db.insert(
      'plots',
      <String, Object?>{
        'client_id': _generateClientId(),
        'farm_local_id': farmLocalId,
        'farm_server_id': farm?.serverId,
        'plot_name': plotName,
        'area_hectares': areaHectares,
        'soil_type': soilType,
        'is_active': isActive ? 1 : 0,
        'local_updated_at': _dateOrNull(now),
        'sync_state': syncStateToString(SyncState.pending),
        'deleted': 0,
        'sync_attempts': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return (await getPlotByLocalId(localId))!;
  }

  Future<void> updatePlotLocal({
    required int localId,
    String? plotName,
    double? areaHectares,
    String? soilType,
    bool? isActive,
  }) async {
    final existing = await getPlotByLocalId(localId);
    if (existing == null) return;
    final now = _nowUtc();
    final baseServer =
        existing.baseServerUpdatedAt ?? (existing.syncState == SyncState.synced
            ? existing.serverUpdatedAt
            : existing.baseServerUpdatedAt);
    final nextSyncState =
        existing.syncState == SyncState.synced ? SyncState.pending : existing.syncState;
    final db = await _db();
    await db.update(
      'plots',
      <String, Object?>{
        'plot_name': plotName ?? existing.plotName,
        'area_hectares': areaHectares ?? existing.areaHectares,
        'soil_type': soilType ?? existing.soilType,
        'is_active': (isActive ?? existing.isActive) ? 1 : 0,
        'local_updated_at': _dateOrNull(now),
        'sync_state': syncStateToString(nextSyncState),
        'base_server_updated_at': _dateOrNull(baseServer),
        'sync_attempts': 0,
        'sync_next_retry_at': null,
        'sync_error': null,
        'conflict_reason': null,
        'deleted': 0,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> deletePlotLocal(int localId) async {
    final existing = await getPlotByLocalId(localId);
    if (existing == null) return;
    final db = await _db();
    final now = _nowUtc();
    await db.delete('plantings', where: 'plot_local_id = ?', whereArgs: [localId]);
    await db.delete('soil_health', where: 'plot_local_id = ?', whereArgs: [localId]);
    if (existing.serverId == null) {
      await db.delete('plots', where: 'local_id = ?', whereArgs: [localId]);
      return;
    }
    await db.update(
      'plots',
      <String, Object?>{
        'deleted': 1,
        'sync_state': syncStateToString(SyncState.pending),
        'local_updated_at': _dateOrNull(now),
        'sync_attempts': 0,
        'sync_next_retry_at': null,
        'sync_error': null,
        'conflict_reason': null,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> purgePlotByLocalId(int localId) async {
    final db = await _db();
    await db.delete('plots', where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<PlantingRecord> createPlantingLocal({
    required int plotLocalId,
    required int cropId,
    required DateTime plantingDate,
    DateTime? expectedHarvestDate,
    String status = '',
    bool isActive = true,
  }) async {
    final db = await _db();
    final now = _nowUtc();
    final plot = await getPlotByLocalId(plotLocalId);
    final localId = await db.insert(
      'plantings',
      <String, Object?>{
        'client_id': _generateClientId(),
        'plot_local_id': plotLocalId,
        'plot_server_id': plot?.serverId,
        'crop_id': cropId,
        'planting_date': _dateOrNull(plantingDate),
        'expected_harvest_date': _dateOrNull(expectedHarvestDate),
        'status': status,
        'is_active': isActive ? 1 : 0,
        'local_updated_at': _dateOrNull(now),
        'sync_state': syncStateToString(SyncState.pending),
        'deleted': 0,
        'sync_attempts': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return (await getPlantingByLocalId(localId))!;
  }

  Future<void> updatePlantingLocal({
    required int localId,
    int? cropId,
    DateTime? plantingDate,
    DateTime? expectedHarvestDate,
    String? status,
    bool? isActive,
  }) async {
    final existing = await getPlantingByLocalId(localId);
    if (existing == null) return;
    final now = _nowUtc();
    final baseServer =
        existing.baseServerUpdatedAt ?? (existing.syncState == SyncState.synced
            ? existing.serverUpdatedAt
            : existing.baseServerUpdatedAt);
    final nextSyncState =
        existing.syncState == SyncState.synced ? SyncState.pending : existing.syncState;
    final db = await _db();
    await db.update(
      'plantings',
      <String, Object?>{
        'crop_id': cropId ?? existing.cropId,
        'planting_date': _dateOrNull(plantingDate ?? existing.plantingDate),
        'expected_harvest_date': _dateOrNull(expectedHarvestDate ?? existing.expectedHarvestDate),
        'status': status ?? existing.status,
        'is_active': (isActive ?? existing.isActive) ? 1 : 0,
        'local_updated_at': _dateOrNull(now),
        'sync_state': syncStateToString(nextSyncState),
        'base_server_updated_at': _dateOrNull(baseServer),
        'sync_attempts': 0,
        'sync_next_retry_at': null,
        'sync_error': null,
        'conflict_reason': null,
        'deleted': 0,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> deletePlantingLocal(int localId) async {
    final existing = await getPlantingByLocalId(localId);
    if (existing == null) return;
    final db = await _db();
    final now = _nowUtc();
    if (existing.serverId == null) {
      await db.delete('plantings', where: 'local_id = ?', whereArgs: [localId]);
      return;
    }
    await db.update(
      'plantings',
      <String, Object?>{
        'deleted': 1,
        'sync_state': syncStateToString(SyncState.pending),
        'local_updated_at': _dateOrNull(now),
        'sync_attempts': 0,
        'sync_next_retry_at': null,
        'sync_error': null,
        'conflict_reason': null,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> purgePlantingByLocalId(int localId) async {
    final db = await _db();
    await db.delete('plantings', where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<SoilHealthRecord> createSoilHealthLocal({
    required int plotLocalId,
    double? phLevel,
    double? nitrogen,
    double? phosphorus,
    double? potassium,
    double? organicMatter,
    double? moistureLevel,
    String? soilType,
    DateTime? testDate,
    String? testMethod,
    String? dataSource,
    String? sensorDeviceId,
    String? sensorReadingId,
    Map<String, dynamic>? sensorPayload,
    Map<String, dynamic>? fieldContext,
    double? confidenceScore,
    String? reviewStatus,
    String? evidencePath,
  }) async {
    final db = await _db();
    final now = _nowUtc();
    final plot = await getPlotByLocalId(plotLocalId);
    final localId = await db.insert(
      'soil_health',
      <String, Object?>{
        'client_id': _generateClientId(),
        'plot_local_id': plotLocalId,
        'plot_server_id': plot?.serverId,
        'ph_level': phLevel,
        'nitrogen': nitrogen,
        'phosphorus': phosphorus,
        'potassium': potassium,
        'organic_matter': organicMatter,
        'moisture_level': moistureLevel,
        'soil_type': soilType,
        'test_date': _dateOrNull(testDate ?? now),
        'test_method': testMethod,
        'data_source': dataSource ?? testMethod ?? 'manual',
        'sensor_device_id': sensorDeviceId,
        'sensor_reading_id': sensorReadingId,
        'sensor_payload': _jsonOrNull(sensorPayload),
        'field_context': _jsonOrNull(fieldContext),
        'confidence_score': confidenceScore,
        'review_status': reviewStatus,
        'review_reason_code': null,
        'review_comment': null,
        'evidence_path': evidencePath,
        'local_updated_at': _dateOrNull(now),
        'sync_state': syncStateToString(SyncState.pending),
        'deleted': 0,
        'sync_attempts': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return (await getSoilHealthByLocalId(localId))!;
  }

  Future<void> updateSoilHealthLocal({
    required int localId,
    double? phLevel,
    double? nitrogen,
    double? phosphorus,
    double? potassium,
    double? organicMatter,
    double? moistureLevel,
    String? soilType,
    DateTime? testDate,
    String? testMethod,
    String? dataSource,
    String? sensorDeviceId,
    String? sensorReadingId,
    Map<String, dynamic>? sensorPayload,
    Map<String, dynamic>? fieldContext,
    double? confidenceScore,
    String? reviewStatus,
    String? evidencePath,
  }) async {
    final existing = await getSoilHealthByLocalId(localId);
    if (existing == null) return;
    final now = _nowUtc();
    final baseServer =
        existing.baseServerUpdatedAt ?? (existing.syncState == SyncState.synced
            ? existing.serverUpdatedAt
            : existing.baseServerUpdatedAt);
    final nextSyncState =
        existing.syncState == SyncState.synced ? SyncState.pending : existing.syncState;
    final db = await _db();
    await db.update(
      'soil_health',
      <String, Object?>{
        'ph_level': phLevel ?? existing.phLevel,
        'nitrogen': nitrogen ?? existing.nitrogen,
        'phosphorus': phosphorus ?? existing.phosphorus,
        'potassium': potassium ?? existing.potassium,
        'organic_matter': organicMatter ?? existing.organicMatter,
        'moisture_level': moistureLevel ?? existing.moistureLevel,
        'soil_type': soilType ?? existing.soilType,
        'test_date': _dateOrNull(testDate ?? existing.testDate),
        'test_method': testMethod ?? existing.testMethod,
        'data_source': dataSource ?? existing.dataSource,
        'sensor_device_id': sensorDeviceId ?? existing.sensorDeviceId,
        'sensor_reading_id': sensorReadingId ?? existing.sensorReadingId,
        'sensor_payload': _jsonOrNull(sensorPayload ?? existing.sensorPayload),
        'field_context': _jsonOrNull(fieldContext ?? existing.fieldContext),
        'confidence_score': confidenceScore ?? existing.confidenceScore,
        'review_status': reviewStatus ?? existing.reviewStatus,
        'review_reason_code': null,
        'review_comment': null,
        'evidence_path': evidencePath ?? existing.evidencePath,
        'local_updated_at': _dateOrNull(now),
        'sync_state': syncStateToString(nextSyncState),
        'base_server_updated_at': _dateOrNull(baseServer),
        'sync_attempts': 0,
        'sync_next_retry_at': null,
        'sync_error': null,
        'conflict_reason': null,
        'deleted': 0,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> deleteSoilHealthLocal(int localId) async {
    final existing = await getSoilHealthByLocalId(localId);
    if (existing == null) return;
    final db = await _db();
    final now = _nowUtc();
    if (existing.serverId == null) {
      await db.delete('soil_health', where: 'local_id = ?', whereArgs: [localId]);
      return;
    }
    await db.update(
      'soil_health',
      <String, Object?>{
        'deleted': 1,
        'sync_state': syncStateToString(SyncState.pending),
        'local_updated_at': _dateOrNull(now),
        'sync_attempts': 0,
        'sync_next_retry_at': null,
        'sync_error': null,
        'conflict_reason': null,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> purgeSoilHealthByLocalId(int localId) async {
    final db = await _db();
    await db.delete('soil_health', where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<List<FarmRecord>> listFarmsNeedingSync() async {
    final db = await _db();
    final rows = await db.query(
      'farms',
      where: "(sync_state IN ('pending','failed')) OR deleted = 1",
    );
    return rows.map(_farmFromRow).toList();
  }

  Future<List<PlotRecord>> listPlotsNeedingSync() async {
    final db = await _db();
    final rows = await db.query(
      'plots',
      where: "(sync_state IN ('pending','failed')) OR deleted = 1",
    );
    return rows.map(_plotFromRow).toList();
  }

  Future<List<PlantingRecord>> listPlantingsNeedingSync() async {
    final db = await _db();
    final rows = await db.query(
      'plantings',
      where: "(sync_state IN ('pending','failed')) OR deleted = 1",
    );
    return rows.map(_plantingFromRow).toList();
  }

  Future<List<SoilHealthRecord>> listSoilHealthNeedingSync() async {
    final db = await _db();
    final rows = await db.query(
      'soil_health',
      where: "(sync_state IN ('pending','failed')) OR deleted = 1",
    );
    return rows.map(_soilFromRow).toList();
  }

  bool readyForRetry(DateTime? nextRetryAt) {
    if (nextRetryAt == null) return true;
    return _nowUtc().isAfter(nextRetryAt);
  }

  Future<void> markFarmSynced({
    required int localId,
    required FarmModel server,
  }) async {
    final db = await _db();
    await db.update(
      'farms',
      <String, Object?>{
        'server_id': server.id,
        'server_created_at': _dateOrNull(server.createdAt),
        'server_updated_at': _dateOrNull(server.updatedAt),
        'base_server_updated_at': null,
        'local_updated_at': _dateOrNull(_nowUtc()),
        'sync_state': syncStateToString(SyncState.synced),
        'deleted': 0,
        'sync_attempts': 0,
        'sync_next_retry_at': null,
        'sync_error': null,
        'conflict_reason': null,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
    await db.update(
      'plots',
      <String, Object?>{'farm_server_id': server.id},
      where: 'farm_local_id = ? AND farm_server_id IS NULL',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markPlotSynced({
    required int localId,
    required PlotModel server,
  }) async {
    final db = await _db();
    await db.update(
      'plots',
      <String, Object?>{
        'server_id': server.id,
        'farm_server_id': server.farmId,
        'server_created_at': _dateOrNull(server.createdAt),
        'server_updated_at': _dateOrNull(server.updatedAt),
        'base_server_updated_at': null,
        'local_updated_at': _dateOrNull(_nowUtc()),
        'sync_state': syncStateToString(SyncState.synced),
        'deleted': 0,
        'sync_attempts': 0,
        'sync_next_retry_at': null,
        'sync_error': null,
        'conflict_reason': null,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
    await db.update(
      'plantings',
      <String, Object?>{'plot_server_id': server.id},
      where: 'plot_local_id = ? AND plot_server_id IS NULL',
      whereArgs: <Object?>[localId],
    );
    await db.update(
      'soil_health',
      <String, Object?>{'plot_server_id': server.id},
      where: 'plot_local_id = ? AND plot_server_id IS NULL',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markPlantingSynced({
    required int localId,
    required PlantingModel server,
  }) async {
    final db = await _db();
    await db.update(
      'plantings',
      <String, Object?>{
        'server_id': server.id,
        'plot_server_id': server.plotId,
        'server_created_at': _dateOrNull(server.createdAt),
        'server_updated_at': _dateOrNull(server.updatedAt),
        'base_server_updated_at': null,
        'local_updated_at': _dateOrNull(_nowUtc()),
        'sync_state': syncStateToString(SyncState.synced),
        'deleted': 0,
        'sync_attempts': 0,
        'sync_next_retry_at': null,
        'sync_error': null,
        'conflict_reason': null,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markSoilHealthSynced({
    required int localId,
    required Map<String, dynamic> server,
  }) async {
    final db = await _db();
    final serverCreated = _parseDate(server['created_at']);
    final serverUpdated = _parseDate(server['updated_at']);
    await db.update(
      'soil_health',
      <String, Object?>{
        'server_id': _toInt(server['id']),
        'plot_server_id': _toNullableInt(server['plot_id']),
        'server_created_at': _dateOrNull(serverCreated),
        'server_updated_at': _dateOrNull(serverUpdated),
        'base_server_updated_at': null,
        'evidence_url': server['evidence_url']?.toString(),
        'review_status': server['review_status']?.toString(),
        'reviewed_by': _toNullableInt(server['reviewed_by']),
        'reviewed_at': _dateOrNull(_parseDate(server['reviewed_at'])),
        'review_reason_code': server['review_reason_code']?.toString(),
        'review_comment': server['review_comment']?.toString(),
        'data_source': server['data_source']?.toString(),
        'sensor_device_id': server['sensor_device_id']?.toString(),
        'sensor_reading_id': server['sensor_reading_id']?.toString(),
        'sensor_payload': _jsonOrNull(_jsonMapOrNull(server['sensor_payload'])),
        'field_context': _jsonOrNull(_jsonMapOrNull(server['field_context'])),
        'confidence_score': _toDouble(server['confidence_score']),
        'evidence_path': null,
        'local_updated_at': _dateOrNull(_nowUtc()),
        'sync_state': syncStateToString(SyncState.synced),
        'deleted': 0,
        'sync_attempts': 0,
        'sync_next_retry_at': null,
        'sync_error': null,
        'conflict_reason': null,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markFarmFailed(int localId, String error, int attempts) async {
    final db = await _db();
    await db.update(
      'farms',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.failed),
        'sync_attempts': attempts,
        'sync_next_retry_at': _dateOrNull(_nextRetryAt(attempts)),
        'sync_error': error,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markFarmPendingRetry(int localId, String error, int attempts) async {
    final db = await _db();
    await db.update(
      'farms',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.pending),
        'sync_attempts': attempts,
        'sync_next_retry_at': _dateOrNull(_nextRetryAt(attempts)),
        'sync_error': error,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markPlotFailed(int localId, String error, int attempts) async {
    final db = await _db();
    await db.update(
      'plots',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.failed),
        'sync_attempts': attempts,
        'sync_next_retry_at': _dateOrNull(_nextRetryAt(attempts)),
        'sync_error': error,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markPlotPendingRetry(int localId, String error, int attempts) async {
    final db = await _db();
    await db.update(
      'plots',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.pending),
        'sync_attempts': attempts,
        'sync_next_retry_at': _dateOrNull(_nextRetryAt(attempts)),
        'sync_error': error,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markPlantingFailed(int localId, String error, int attempts) async {
    final db = await _db();
    await db.update(
      'plantings',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.failed),
        'sync_attempts': attempts,
        'sync_next_retry_at': _dateOrNull(_nextRetryAt(attempts)),
        'sync_error': error,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markPlantingPendingRetry(int localId, String error, int attempts) async {
    final db = await _db();
    await db.update(
      'plantings',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.pending),
        'sync_attempts': attempts,
        'sync_next_retry_at': _dateOrNull(_nextRetryAt(attempts)),
        'sync_error': error,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markPlantingBlocked(int localId, String message) async {
    final db = await _db();
    await db.update(
      'plantings',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.pending),
        'sync_next_retry_at': null,
        'sync_error': message,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markSoilHealthFailed(int localId, String error, int attempts) async {
    final db = await _db();
    await db.update(
      'soil_health',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.failed),
        'sync_attempts': attempts,
        'sync_next_retry_at': _dateOrNull(_nextRetryAt(attempts)),
        'sync_error': error,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markSoilHealthPendingRetry(int localId, String error, int attempts) async {
    final db = await _db();
    await db.update(
      'soil_health',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.pending),
        'sync_attempts': attempts,
        'sync_next_retry_at': _dateOrNull(_nextRetryAt(attempts)),
        'sync_error': error,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markFarmConflict(int localId, String reason) async {
    final db = await _db();
    await db.update(
      'farms',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.conflict),
        'conflict_reason': reason,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markPlotConflict(int localId, String reason) async {
    final db = await _db();
    await db.update(
      'plots',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.conflict),
        'conflict_reason': reason,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markPlantingConflict(int localId, String reason) async {
    final db = await _db();
    await db.update(
      'plantings',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.conflict),
        'conflict_reason': reason,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markSoilHealthConflict(int localId, String reason) async {
    final db = await _db();
    await db.update(
      'soil_health',
      <String, Object?>{
        'sync_state': syncStateToString(SyncState.conflict),
        'conflict_reason': reason,
      },
      where: 'local_id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> mergeFarmsFromServer(List<FarmModel> farms) async {
    final db = await _db();
    final now = _nowUtc();
    final localRows = await db.query('farms', where: 'server_id IS NOT NULL');
    final localByServerId = <int, Map<String, Object?>>{};
    for (final row in localRows) {
      final serverId = _toNullableInt(row['server_id']);
      if (serverId != null) {
        localByServerId[serverId] = row;
      }
    }
    final serverIds = <int>{};
    final batch = db.batch();

    for (final farm in farms) {
      serverIds.add(farm.id);
      final local = localByServerId[farm.id];
      if (local == null) {
        batch.insert(
          'farms',
          <String, Object?>{
            'server_id': farm.id,
            'region_id': farm.regionId,
            'farm_name': farm.farmName,
            'latitude': farm.latitude,
            'longitude': farm.longitude,
            'area_hectares': farm.areaHectares,
            'farm_type': farm.farmType,
            'is_active': farm.isActive ? 1 : 0,
            'server_created_at': _dateOrNull(farm.createdAt),
            'server_updated_at': _dateOrNull(farm.updatedAt),
            'local_updated_at': _dateOrNull(now),
            'sync_state': syncStateToString(SyncState.synced),
            'deleted': 0,
            'sync_attempts': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        final syncState = syncStateFromString(local['sync_state']?.toString());
        final deleted = _toBool(local['deleted']);
        if (syncState == SyncState.synced && !deleted) {
          batch.update(
            'farms',
            <String, Object?>{
              'region_id': farm.regionId,
              'farm_name': farm.farmName,
              'latitude': farm.latitude,
              'longitude': farm.longitude,
              'area_hectares': farm.areaHectares,
              'farm_type': farm.farmType,
              'is_active': farm.isActive ? 1 : 0,
              'server_created_at': _dateOrNull(farm.createdAt),
              'server_updated_at': _dateOrNull(farm.updatedAt),
              'local_updated_at': _dateOrNull(now),
            },
            where: 'local_id = ?',
            whereArgs: <Object?>[local['local_id']],
          );
        } else {
          batch.update(
            'farms',
            <String, Object?>{
              'server_created_at': _dateOrNull(farm.createdAt),
              'server_updated_at': _dateOrNull(farm.updatedAt),
            },
            where: 'local_id = ?',
            whereArgs: <Object?>[local['local_id']],
          );
        }
      }
    }

    for (final local in localRows) {
      final serverId = _toNullableInt(local['server_id']);
      if (serverId == null || serverIds.contains(serverId)) continue;
      final syncState = syncStateFromString(local['sync_state']?.toString());
      final deleted = _toBool(local['deleted']);
      if (syncState == SyncState.synced && !deleted) {
        batch.delete('farms', where: 'local_id = ?', whereArgs: [local['local_id']]);
      }
    }

    await batch.commit(noResult: true);
  }

  Future<void> mergePlotsFromServer({
    required int farmServerId,
    required List<PlotModel> plots,
  }) async {
    final db = await _db();
    final now = _nowUtc();
    final localRows = await db.query(
      'plots',
      where: 'farm_server_id = ?',
      whereArgs: [farmServerId],
    );
    final localByServerId = <int, Map<String, Object?>>{};
    for (final row in localRows) {
      final serverId = _toNullableInt(row['server_id']);
      if (serverId != null) {
        localByServerId[serverId] = row;
      }
    }

    final farmRow =
        await db.query('farms', where: 'server_id = ?', whereArgs: [farmServerId]);
    final farmLocalId = farmRow.isNotEmpty ? _toNullableInt(farmRow.first['local_id']) : null;

    final serverIds = <int>{};
    final batch = db.batch();

    for (final plot in plots) {
      serverIds.add(plot.id);
      final local = localByServerId[plot.id];
      if (local == null) {
        batch.insert(
          'plots',
          <String, Object?>{
            'server_id': plot.id,
            'farm_local_id': farmLocalId,
            'farm_server_id': plot.farmId,
            'plot_name': plot.plotName,
            'area_hectares': plot.areaHectares,
            'soil_type': plot.soilType,
            'is_active': plot.isActive ? 1 : 0,
            'server_created_at': _dateOrNull(plot.createdAt),
            'server_updated_at': _dateOrNull(plot.updatedAt),
            'local_updated_at': _dateOrNull(now),
            'sync_state': syncStateToString(SyncState.synced),
            'deleted': 0,
            'sync_attempts': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        final syncState = syncStateFromString(local['sync_state']?.toString());
        final deleted = _toBool(local['deleted']);
        if (syncState == SyncState.synced && !deleted) {
          batch.update(
            'plots',
            <String, Object?>{
              'farm_local_id': farmLocalId,
              'farm_server_id': plot.farmId,
              'plot_name': plot.plotName,
              'area_hectares': plot.areaHectares,
              'soil_type': plot.soilType,
              'is_active': plot.isActive ? 1 : 0,
              'server_created_at': _dateOrNull(plot.createdAt),
              'server_updated_at': _dateOrNull(plot.updatedAt),
              'local_updated_at': _dateOrNull(now),
            },
            where: 'local_id = ?',
            whereArgs: <Object?>[local['local_id']],
          );
        } else {
          batch.update(
            'plots',
            <String, Object?>{
              'farm_local_id': farmLocalId,
              'farm_server_id': plot.farmId,
              'server_created_at': _dateOrNull(plot.createdAt),
              'server_updated_at': _dateOrNull(plot.updatedAt),
            },
            where: 'local_id = ?',
            whereArgs: <Object?>[local['local_id']],
          );
        }
      }
    }

    for (final local in localRows) {
      final serverId = _toNullableInt(local['server_id']);
      if (serverId == null || serverIds.contains(serverId)) continue;
      final syncState = syncStateFromString(local['sync_state']?.toString());
      final deleted = _toBool(local['deleted']);
      if (syncState == SyncState.synced && !deleted) {
        batch.delete('plots', where: 'local_id = ?', whereArgs: [local['local_id']]);
      }
    }

    await batch.commit(noResult: true);
  }

  Future<void> mergePlantingsFromServer({
    required int plotServerId,
    required List<PlantingModel> plantings,
  }) async {
    final db = await _db();
    final now = _nowUtc();
    final localRows = await db.query(
      'plantings',
      where: 'plot_server_id = ?',
      whereArgs: [plotServerId],
    );
    final localByServerId = <int, Map<String, Object?>>{};
    for (final row in localRows) {
      final serverId = _toNullableInt(row['server_id']);
      if (serverId != null) {
        localByServerId[serverId] = row;
      }
    }

    final plotRow =
        await db.query('plots', where: 'server_id = ?', whereArgs: [plotServerId]);
    final plotLocalId = plotRow.isNotEmpty ? _toNullableInt(plotRow.first['local_id']) : null;

    final serverIds = <int>{};
    final batch = db.batch();

    for (final planting in plantings) {
      serverIds.add(planting.id);
      final local = localByServerId[planting.id];
      if (local == null) {
        batch.insert(
          'plantings',
          <String, Object?>{
            'server_id': planting.id,
            'plot_local_id': plotLocalId,
            'plot_server_id': planting.plotId,
            'crop_id': planting.cropId,
            'planting_date': _dateOrNull(planting.plantingDate),
            'expected_harvest_date': _dateOrNull(planting.expectedHarvestDate),
            'status': planting.status,
            'is_active': planting.isActive ? 1 : 0,
            'server_created_at': _dateOrNull(planting.createdAt),
            'server_updated_at': _dateOrNull(planting.updatedAt),
            'local_updated_at': _dateOrNull(now),
            'sync_state': syncStateToString(SyncState.synced),
            'deleted': 0,
            'sync_attempts': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        final syncState = syncStateFromString(local['sync_state']?.toString());
        final deleted = _toBool(local['deleted']);
        if (syncState == SyncState.synced && !deleted) {
          batch.update(
            'plantings',
            <String, Object?>{
              'plot_local_id': plotLocalId,
              'plot_server_id': planting.plotId,
              'crop_id': planting.cropId,
              'planting_date': _dateOrNull(planting.plantingDate),
              'expected_harvest_date': _dateOrNull(planting.expectedHarvestDate),
              'status': planting.status,
              'is_active': planting.isActive ? 1 : 0,
              'server_created_at': _dateOrNull(planting.createdAt),
              'server_updated_at': _dateOrNull(planting.updatedAt),
              'local_updated_at': _dateOrNull(now),
            },
            where: 'local_id = ?',
            whereArgs: <Object?>[local['local_id']],
          );
        } else {
          batch.update(
            'plantings',
            <String, Object?>{
              'plot_local_id': plotLocalId,
              'plot_server_id': planting.plotId,
              'server_created_at': _dateOrNull(planting.createdAt),
              'server_updated_at': _dateOrNull(planting.updatedAt),
            },
            where: 'local_id = ?',
            whereArgs: <Object?>[local['local_id']],
          );
        }
      }
    }

    for (final local in localRows) {
      final serverId = _toNullableInt(local['server_id']);
      if (serverId == null || serverIds.contains(serverId)) continue;
      final syncState = syncStateFromString(local['sync_state']?.toString());
      final deleted = _toBool(local['deleted']);
      if (syncState == SyncState.synced && !deleted) {
        batch.delete('plantings', where: 'local_id = ?', whereArgs: [local['local_id']]);
      }
    }

    await batch.commit(noResult: true);
  }

  Future<void> mergeSoilHealthFromServer(List<Map<String, dynamic>> items) async {
    final db = await _db();
    final now = _nowUtc();
    final localRows = await db.query('soil_health', where: 'server_id IS NOT NULL');
    final localByServerId = <int, Map<String, Object?>>{};
    for (final row in localRows) {
      final serverId = _toNullableInt(row['server_id']);
      if (serverId != null) {
        localByServerId[serverId] = row;
      }
    }

    final plotRows = await db.query(
      'plots',
      columns: ['local_id', 'server_id'],
      where: 'server_id IS NOT NULL',
    );
    final plotLocalByServerId = <int, int>{};
    for (final row in plotRows) {
      final serverId = _toNullableInt(row['server_id']);
      final localId = _toNullableInt(row['local_id']);
      if (serverId != null && localId != null) {
        plotLocalByServerId[serverId] = localId;
      }
    }

    final serverIds = <int>{};
    final batch = db.batch();

    for (final item in items) {
      final serverId = _toNullableInt(item['id']);
      if (serverId == null) continue;
      serverIds.add(serverId);
      final local = localByServerId[serverId];
      final plotServerId = _toNullableInt(item['plot_id']);
      final plotLocalId = plotServerId == null ? null : plotLocalByServerId[plotServerId];
      final serverCreated = _parseDate(item['created_at']);
      final serverUpdated = _parseDate(item['updated_at']);
      final testDate =
          _parseDate(item['test_date']) ?? _parseDate(item['tested_at']) ?? serverCreated;
      if (local == null) {
        batch.insert(
          'soil_health',
          <String, Object?>{
            'server_id': serverId,
            'plot_local_id': plotLocalId,
            'plot_server_id': plotServerId,
            'ph_level': _toDouble(item['ph_level']),
            'nitrogen': _toDouble(item['nitrogen']),
            'phosphorus': _toDouble(item['phosphorus']),
            'potassium': _toDouble(item['potassium']),
            'organic_matter': _toDouble(item['organic_matter']),
            'moisture_level': _toDouble(item['moisture_level'] ?? item['moisture']),
            'soil_type': item['soil_type']?.toString(),
            'test_date': _dateOrNull(testDate),
            'test_method': item['test_method']?.toString(),
            'data_source': item['data_source']?.toString(),
            'sensor_device_id': item['sensor_device_id']?.toString(),
            'sensor_reading_id': item['sensor_reading_id']?.toString(),
            'sensor_payload': _jsonOrNull(_jsonMapOrNull(item['sensor_payload'])),
            'field_context': _jsonOrNull(_jsonMapOrNull(item['field_context'])),
            'confidence_score': _toDouble(item['confidence_score']),
            'review_status': item['review_status']?.toString(),
            'reviewed_by': _toNullableInt(item['reviewed_by']),
            'reviewed_at': _dateOrNull(_parseDate(item['reviewed_at'])),
            'review_reason_code': item['review_reason_code']?.toString(),
            'review_comment': item['review_comment']?.toString(),
            'evidence_url': item['evidence_url']?.toString(),
            'server_created_at': _dateOrNull(serverCreated),
            'server_updated_at': _dateOrNull(serverUpdated),
            'local_updated_at': _dateOrNull(now),
            'sync_state': syncStateToString(SyncState.synced),
            'deleted': 0,
            'sync_attempts': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        final syncState = syncStateFromString(local['sync_state']?.toString());
        final deleted = _toBool(local['deleted']);
        if (syncState == SyncState.synced && !deleted) {
          batch.update(
            'soil_health',
            <String, Object?>{
              'plot_local_id': plotLocalId,
              'plot_server_id': plotServerId,
              'ph_level': _toDouble(item['ph_level']),
              'nitrogen': _toDouble(item['nitrogen']),
              'phosphorus': _toDouble(item['phosphorus']),
              'potassium': _toDouble(item['potassium']),
              'organic_matter': _toDouble(item['organic_matter']),
              'moisture_level': _toDouble(item['moisture_level'] ?? item['moisture']),
              'soil_type': item['soil_type']?.toString(),
              'test_date': _dateOrNull(testDate),
              'test_method': item['test_method']?.toString(),
              'data_source': item['data_source']?.toString(),
              'sensor_device_id': item['sensor_device_id']?.toString(),
              'sensor_reading_id': item['sensor_reading_id']?.toString(),
              'sensor_payload': _jsonOrNull(_jsonMapOrNull(item['sensor_payload'])),
              'field_context': _jsonOrNull(_jsonMapOrNull(item['field_context'])),
              'confidence_score': _toDouble(item['confidence_score']),
              'review_status': item['review_status']?.toString(),
              'reviewed_by': _toNullableInt(item['reviewed_by']),
              'reviewed_at': _dateOrNull(_parseDate(item['reviewed_at'])),
              'review_reason_code': item['review_reason_code']?.toString(),
              'review_comment': item['review_comment']?.toString(),
              'evidence_url': item['evidence_url']?.toString(),
              'server_created_at': _dateOrNull(serverCreated),
              'server_updated_at': _dateOrNull(serverUpdated),
              'local_updated_at': _dateOrNull(now),
            },
            where: 'local_id = ?',
            whereArgs: <Object?>[local['local_id']],
          );
        } else {
          batch.update(
            'soil_health',
            <String, Object?>{
              'plot_local_id': plotLocalId,
              'plot_server_id': plotServerId,
              'server_created_at': _dateOrNull(serverCreated),
              'server_updated_at': _dateOrNull(serverUpdated),
            },
            where: 'local_id = ?',
            whereArgs: <Object?>[local['local_id']],
          );
        }
      }
    }

    for (final local in localRows) {
      final serverId = _toNullableInt(local['server_id']);
      if (serverId == null || serverIds.contains(serverId)) continue;
      final syncState = syncStateFromString(local['sync_state']?.toString());
      final deleted = _toBool(local['deleted']);
      if (syncState == SyncState.synced && !deleted) {
        batch.delete('soil_health', where: 'local_id = ?', whereArgs: [local['local_id']]);
      }
    }

    await batch.commit(noResult: true);
  }
}
