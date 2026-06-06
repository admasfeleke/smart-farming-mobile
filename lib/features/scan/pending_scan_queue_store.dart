import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class PendingScanQueueEntry {
  final String queueId;
  final int plotId;
  final int cropId;
  final int? plantingId;
  final String imagePath;
  final DateTime capturedAtUtc;
  final int attempts;
  final DateTime nextRetryAtUtc;
  final DateTime createdAtUtc;
  final Map<String, dynamic>? scanMetadata;

  const PendingScanQueueEntry({
    required this.queueId,
    required this.plotId,
    required this.cropId,
    required this.plantingId,
    required this.imagePath,
    required this.capturedAtUtc,
    required this.attempts,
    required this.nextRetryAtUtc,
    required this.createdAtUtc,
    required this.scanMetadata,
  });
}

class PendingScanQueueStore {
  PendingScanQueueStore._();

  static final PendingScanQueueStore instance = PendingScanQueueStore._();

  static const String _table = 'pending_scans';
  Database? _db;

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null) return existing;
    final appDir = await getApplicationSupportDirectory();
    final dbPath =
        '${appDir.path}${Platform.pathSeparator}pending_scan_queue.db';
    final db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE $_table (
            queue_id TEXT PRIMARY KEY,
            plot_id INTEGER NOT NULL,
            crop_id INTEGER NOT NULL,
            planting_id INTEGER NULL,
            image_path TEXT NOT NULL,
            captured_at TEXT NOT NULL,
            attempts INTEGER NOT NULL,
            next_retry_at TEXT NOT NULL,
            created_at TEXT NOT NULL,
            scan_metadata_json TEXT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX idx_pending_scans_next_retry ON $_table(next_retry_at)',
        );
        await database.execute(
          'CREATE INDEX idx_pending_scans_created_at ON $_table(created_at)',
        );
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            'ALTER TABLE $_table ADD COLUMN scan_metadata_json TEXT NULL',
          );
        }
      },
    );
    _db = db;
    return db;
  }

  Future<void> enqueue(PendingScanQueueEntry entry) async {
    final db = await _database();
    await db.insert(
      _table,
      <String, Object?>{
        'queue_id': entry.queueId,
        'plot_id': entry.plotId,
        'crop_id': entry.cropId,
        'planting_id': entry.plantingId,
        'image_path': entry.imagePath,
        'captured_at': entry.capturedAtUtc.toIso8601String(),
        'attempts': entry.attempts,
        'next_retry_at': entry.nextRetryAtUtc.toIso8601String(),
        'created_at': entry.createdAtUtc.toIso8601String(),
        'scan_metadata_json': entry.scanMetadata == null
            ? null
            : jsonEncode(entry.scanMetadata),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PendingScanQueueEntry>> listAll() async {
    final db = await _database();
    final rows = await db.query(_table, orderBy: 'created_at ASC');
    return rows.map(_fromRow).toList();
  }

  Future<List<PendingScanQueueEntry>> listReady({
    required DateTime nowUtc,
    int limit = 40,
  }) async {
    final db = await _database();
    final rows = await db.query(
      _table,
      where: 'next_retry_at <= ?',
      whereArgs: <Object?>[nowUtc.toIso8601String()],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> deleteByQueueId(String queueId) async {
    final db = await _database();
    await db.delete(_table, where: 'queue_id = ?', whereArgs: <Object?>[queueId]);
  }

  Future<void> clearAll() async {
    final db = await _database();
    await db.delete(_table);
  }

  Future<void> updateRetry({
    required String queueId,
    required int attempts,
    required DateTime nextRetryAtUtc,
  }) async {
    final db = await _database();
    await db.update(
      _table,
      <String, Object?>{
        'attempts': attempts,
        'next_retry_at': nextRetryAtUtc.toIso8601String(),
      },
      where: 'queue_id = ?',
      whereArgs: <Object?>[queueId],
    );
  }

  PendingScanQueueEntry _fromRow(Map<String, Object?> row) {
    final queueId = row['queue_id']?.toString() ?? '';
    final plotId = row['plot_id'] is num ? (row['plot_id'] as num).toInt() : 0;
    final cropId = row['crop_id'] is num ? (row['crop_id'] as num).toInt() : 0;
    final plantingId = row['planting_id'] is num
        ? (row['planting_id'] as num).toInt()
        : null;
    final imagePath = row['image_path']?.toString() ?? '';
    final capturedAtUtc =
        DateTime.tryParse(row['captured_at']?.toString() ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final attempts =
        row['attempts'] is num ? (row['attempts'] as num).toInt() : 0;
    final nextRetryAtUtc =
        DateTime.tryParse(row['next_retry_at']?.toString() ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final createdAtUtc =
        DateTime.tryParse(row['created_at']?.toString() ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    Map<String, dynamic>? scanMetadata;
    final scanMetadataRaw = row['scan_metadata_json']?.toString().trim() ?? '';
    if (scanMetadataRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(scanMetadataRaw);
        if (decoded is Map<String, dynamic>) {
          scanMetadata = decoded;
        }
      } catch (_) {
        scanMetadata = null;
      }
    }

    return PendingScanQueueEntry(
      queueId: queueId,
      plotId: plotId,
      cropId: cropId,
      plantingId: plantingId,
      imagePath: imagePath,
      capturedAtUtc: capturedAtUtc,
      attempts: attempts,
      nextRetryAtUtc: nextRetryAtUtc,
      createdAtUtc: createdAtUtc,
      scanMetadata: scanMetadata,
    );
  }
}
