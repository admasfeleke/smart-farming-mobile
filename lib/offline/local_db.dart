import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalDb {
  LocalDb._();

  static final LocalDb instance = LocalDb._();
  static const int _dbVersion = 3;
  static const String _dbName = 'smart_farm_local.db';

  Database? _db;

  Future<Database> database() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}${Platform.pathSeparator}$_dbName';
    final db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (database, _) async {
        await database.execute(_createFarmsTable);
        await database.execute(_createPlotsTable);
        await database.execute(_createPlantingsTable);
        await database.execute(_createSoilHealthTable);
        await database.execute('CREATE INDEX idx_farms_server_id ON farms(server_id)');
        await database.execute('CREATE INDEX idx_plots_server_id ON plots(server_id)');
        await database.execute('CREATE INDEX idx_plantings_server_id ON plantings(server_id)');
        await database.execute('CREATE INDEX idx_soil_server_id ON soil_health(server_id)');
        await database.execute('CREATE INDEX idx_plots_farm_local ON plots(farm_local_id)');
        await database.execute('CREATE INDEX idx_plantings_plot_local ON plantings(plot_local_id)');
        await database.execute('CREATE INDEX idx_soil_plot_local ON soil_health(plot_local_id)');
        await database.execute('CREATE INDEX idx_farms_sync_state ON farms(sync_state)');
        await database.execute('CREATE INDEX idx_plots_sync_state ON plots(sync_state)');
        await database.execute('CREATE INDEX idx_plantings_sync_state ON plantings(sync_state)');
        await database.execute('CREATE INDEX idx_soil_sync_state ON soil_health(sync_state)');
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _ensureColumn(
            database,
            'soil_health',
            'review_reason_code',
            'TEXT',
          );
          await _ensureColumn(
            database,
            'soil_health',
            'review_comment',
            'TEXT',
          );
        }
        if (oldVersion < 3) {
          await _ensureColumn(database, 'soil_health', 'data_source', 'TEXT');
          await _ensureColumn(database, 'soil_health', 'sensor_device_id', 'TEXT');
          await _ensureColumn(database, 'soil_health', 'sensor_reading_id', 'TEXT');
          await _ensureColumn(database, 'soil_health', 'sensor_payload', 'TEXT');
          await _ensureColumn(database, 'soil_health', 'field_context', 'TEXT');
          await _ensureColumn(database, 'soil_health', 'confidence_score', 'REAL');
        }
      },
    );
    _db = db;
    return db;
  }

  static Future<void> _ensureColumn(
    Database database,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> clearFarmerOwnedData() async {
    final db = await database();
    await db.transaction((txn) async {
      await txn.delete('soil_health');
      await txn.delete('plantings');
      await txn.delete('plots');
      await txn.delete('farms');
    });
  }

  static const String _createFarmsTable = '''
    CREATE TABLE farms (
      local_id INTEGER PRIMARY KEY AUTOINCREMENT,
      server_id INTEGER UNIQUE,
      client_id TEXT,
      region_id INTEGER NOT NULL,
      farm_name TEXT NOT NULL,
      latitude REAL,
      longitude REAL,
      area_hectares REAL,
      farm_type TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      server_created_at TEXT,
      server_updated_at TEXT,
      base_server_updated_at TEXT,
      local_updated_at TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'synced',
      deleted INTEGER NOT NULL DEFAULT 0,
      conflict_reason TEXT,
      sync_attempts INTEGER NOT NULL DEFAULT 0,
      sync_next_retry_at TEXT,
      sync_error TEXT
    )
  ''';

  static const String _createPlotsTable = '''
    CREATE TABLE plots (
      local_id INTEGER PRIMARY KEY AUTOINCREMENT,
      server_id INTEGER UNIQUE,
      client_id TEXT,
      farm_local_id INTEGER,
      farm_server_id INTEGER,
      plot_name TEXT NOT NULL,
      area_hectares REAL,
      soil_type TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      server_created_at TEXT,
      server_updated_at TEXT,
      base_server_updated_at TEXT,
      local_updated_at TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'synced',
      deleted INTEGER NOT NULL DEFAULT 0,
      conflict_reason TEXT,
      sync_attempts INTEGER NOT NULL DEFAULT 0,
      sync_next_retry_at TEXT,
      sync_error TEXT
    )
  ''';

  static const String _createPlantingsTable = '''
    CREATE TABLE plantings (
      local_id INTEGER PRIMARY KEY AUTOINCREMENT,
      server_id INTEGER UNIQUE,
      client_id TEXT,
      plot_local_id INTEGER,
      plot_server_id INTEGER,
      crop_id INTEGER NOT NULL,
      planting_date TEXT NOT NULL,
      expected_harvest_date TEXT,
      status TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      server_created_at TEXT,
      server_updated_at TEXT,
      base_server_updated_at TEXT,
      local_updated_at TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'synced',
      deleted INTEGER NOT NULL DEFAULT 0,
      conflict_reason TEXT,
      sync_attempts INTEGER NOT NULL DEFAULT 0,
      sync_next_retry_at TEXT,
      sync_error TEXT
    )
  ''';

  static const String _createSoilHealthTable = '''
    CREATE TABLE soil_health (
      local_id INTEGER PRIMARY KEY AUTOINCREMENT,
      server_id INTEGER UNIQUE,
      client_id TEXT,
      plot_local_id INTEGER,
      plot_server_id INTEGER,
      ph_level REAL,
      nitrogen REAL,
      phosphorus REAL,
      potassium REAL,
      organic_matter REAL,
      moisture_level REAL,
      soil_type TEXT,
      test_date TEXT,
      test_method TEXT,
      data_source TEXT,
      sensor_device_id TEXT,
      sensor_reading_id TEXT,
      sensor_payload TEXT,
      field_context TEXT,
      confidence_score REAL,
      review_status TEXT,
      reviewed_by INTEGER,
      reviewed_at TEXT,
      review_reason_code TEXT,
      review_comment TEXT,
      evidence_path TEXT,
      evidence_url TEXT,
      server_created_at TEXT,
      server_updated_at TEXT,
      base_server_updated_at TEXT,
      local_updated_at TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'synced',
      deleted INTEGER NOT NULL DEFAULT 0,
      conflict_reason TEXT,
      sync_attempts INTEGER NOT NULL DEFAULT 0,
      sync_next_retry_at TEXT,
      sync_error TEXT
    )
  ''';
}
