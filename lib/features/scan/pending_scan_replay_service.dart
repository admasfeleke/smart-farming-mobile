import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import '../../api_client.dart';
import '../../sync_refresh_notifier.dart';
import 'local_scan_history_store.dart';
import 'pending_scan_queue_store.dart';

class PendingScanReplayService {
  PendingScanReplayService._();

  static final PendingScanReplayService instance = PendingScanReplayService._();

  static const int _maxPendingQueueItems = 60;
  static const Duration _maxPendingQueueAge = Duration(days: 7);
  static const int _maxPendingRetryAttempts = 5;
  static const Duration _initialPendingRetryDelay = Duration(minutes: 1);
  static const Duration _maxPendingRetryDelay = Duration(hours: 12);
  static const int _structuredCaptureRequiredShots = 2;

  static void _logReplayEvent(String event, Map<String, Object?> payload) {
    developer.log(event, name: 'smart_farm.scan.replay', error: payload);
  }

  Future<void> drainReadyOnce() async {
    final store = PendingScanQueueStore.instance;
    var queueChanged = await _prunePendingQueue();
    final ready = await store.listReady(
      nowUtc: DateTime.now().toUtc(),
      limit: _maxPendingQueueItems,
    );
    if (ready.isEmpty) {
      if (queueChanged) {
        notifySyncRefresh();
      }
      return;
    }

    for (final entry in ready) {
      final imageMissing =
          entry.imagePath.isEmpty || !await File(entry.imagePath).exists();
      final expired = _isQueuedEntryExpired(entry.capturedAtUtc);
      if (imageMissing || expired) {
        _logReplayEvent('drop.invalid_entry', <String, Object?>{
          'queue_id': entry.queueId,
          'image_missing': imageMissing,
          'expired': expired,
          'attempts': entry.attempts,
        });
        await store.deleteByQueueId(entry.queueId);
        queueChanged = true;
        if (entry.imagePath.isNotEmpty) {
          await _deleteManagedQueuedImage(entry.imagePath);
        }
        continue;
      }
      try {
        final createdReport = await ApiClient.createDiseaseReport(
          plotId: entry.plotId,
          cropId: entry.cropId,
          plantingId: entry.plantingId,
          imagePath: entry.imagePath,
          capturedAt: entry.capturedAtUtc,
          submissionId: entry.queueId,
          growthStage: _metadataString(entry.scanMetadata, 'growth_stage'),
          symptomDays: _metadataInt(entry.scanMetadata, 'symptom_days'),
          recentRain: _metadataBool(entry.scanMetadata, 'recent_rain'),
          fieldNotes: _metadataString(entry.scanMetadata, 'field_notes'),
          captureShots:
              _metadataInt(entry.scanMetadata, 'capture_shots') ??
              _structuredCaptureRequiredShots,
          captureProtocol:
              _metadataString(entry.scanMetadata, 'capture_protocol') ??
              'guided_multi_leaf_offline',
          provisionalDiseaseName: _metadataString(
            entry.scanMetadata,
            'offline_local_disease_name',
          ),
          provisionalCanonicalDiseaseName: _metadataString(
            entry.scanMetadata,
            'offline_local_disease_key',
          ),
          provisionalSeverity: _metadataString(
            entry.scanMetadata,
            'offline_local_severity',
          ),
          provisionalConfidence: _metadataDouble(
            entry.scanMetadata,
            'offline_local_confidence',
          ),
          provisionalInferenceMessage: _metadataString(
            entry.scanMetadata,
            'offline_local_inference',
          ),
          provisionalInferenceUnavailable: _metadataString(
            entry.scanMetadata,
            'offline_local_inference_unavailable',
          ),
        );
        _logReplayEvent('replay.success', <String, Object?>{
          'queue_id': entry.queueId,
          'attempts': entry.attempts,
        });
        await store.deleteByQueueId(entry.queueId);
        queueChanged = true;
        final keptForHistory = await _keepSyncedLocalHistoryIfNeeded(
          entry: entry,
          submissionId: createdReport.clientSubmissionId,
          serverNeedsReview:
              !createdReport.finding.isInferred &&
              !createdReport.finding.isVerified,
        );
        if (!keptForHistory) {
          await _deleteManagedQueuedImage(entry.imagePath);
        }
      } on ApiUnauthorized {
        _logReplayEvent('replay.paused_unauthorized', <String, Object?>{
          'queue_id': entry.queueId,
          'attempts': entry.attempts,
        });
        break;
      } catch (_) {
        final nextAttempts = entry.attempts + 1;
        if (nextAttempts >= _maxPendingRetryAttempts) {
          _logReplayEvent('replay.drop_max_attempts', <String, Object?>{
            'queue_id': entry.queueId,
            'attempts': nextAttempts,
          });
          await store.updateRetry(
            queueId: entry.queueId,
            attempts: nextAttempts,
            nextRetryAtUtc: DateTime.now().toUtc().add(_maxPendingRetryDelay),
          );
          queueChanged = true;
          continue;
        }
        _logReplayEvent('replay.retry_scheduled', <String, Object?>{
          'queue_id': entry.queueId,
          'attempts': nextAttempts,
        });
        await store.updateRetry(
          queueId: entry.queueId,
          attempts: nextAttempts,
          nextRetryAtUtc: _nextRetryAt(nextAttempts),
        );
        queueChanged = true;
      }
    }
    if (queueChanged) {
      notifySyncRefresh();
    }
  }

  Future<bool> _keepSyncedLocalHistoryIfNeeded({
    required PendingScanQueueEntry entry,
    required String? submissionId,
    required bool serverNeedsReview,
  }) async {
    if (!serverNeedsReview ||
        !_hasMeaningfulOfflineFinding(entry.scanMetadata)) {
      return false;
    }
    final resolvedSubmissionId = submissionId?.trim().isNotEmpty == true
        ? submissionId!.trim()
        : entry.queueId;
    if (resolvedSubmissionId.trim().isEmpty) {
      return false;
    }
    await LocalScanHistoryStore.instance.upsert(
      LocalScanHistoryEntry(
        submissionId: resolvedSubmissionId,
        plotId: entry.plotId,
        cropId: entry.cropId,
        plantingId: entry.plantingId,
        imagePath: entry.imagePath,
        capturedAtUtc: entry.capturedAtUtc.toUtc(),
        syncedAtUtc: DateTime.now().toUtc(),
        scanMetadata: entry.scanMetadata == null
            ? null
            : Map<String, dynamic>.from(entry.scanMetadata!),
      ),
    );
    return true;
  }

  bool _hasMeaningfulOfflineFinding(Map<String, dynamic>? metadata) {
    final value = metadata?['offline_local_disease_name']?.toString().trim();
    return value != null && value.isNotEmpty;
  }

  Future<bool> _prunePendingQueue() async {
    final store = PendingScanQueueStore.instance;
    final all = await store.listAll();
    final survivors = <PendingScanQueueEntry>[];
    var changed = false;
    for (final entry in all) {
      final imageMissing =
          entry.imagePath.isEmpty || !await File(entry.imagePath).exists();
      final expired = _isQueuedEntryExpired(entry.capturedAtUtc);
      if (imageMissing || expired) {
        await store.deleteByQueueId(entry.queueId);
        changed = true;
        if (entry.imagePath.isNotEmpty) {
          await _deleteManagedQueuedImage(entry.imagePath);
        }
        continue;
      }
      survivors.add(entry);
    }

    if (survivors.length <= _maxPendingQueueItems) {
      return changed;
    }

    final overflow = survivors.length - _maxPendingQueueItems;
    for (var i = 0; i < overflow; i++) {
      final entry = survivors[i];
      await store.deleteByQueueId(entry.queueId);
      changed = true;
      if (entry.imagePath.isNotEmpty) {
        await _deleteManagedQueuedImage(entry.imagePath);
      }
    }
    return changed;
  }

  bool _isQueuedEntryExpired(DateTime capturedAt) {
    return DateTime.now().difference(capturedAt.toUtc()) > _maxPendingQueueAge;
  }

  DateTime _nextRetryAt(int attempts) {
    final boundedAttempts = attempts < 1 ? 1 : attempts;
    final multiplier = math.pow(2, boundedAttempts - 1).toInt();
    final seconds = _initialPendingRetryDelay.inSeconds * multiplier;
    final boundedSeconds = seconds > _maxPendingRetryDelay.inSeconds
        ? _maxPendingRetryDelay.inSeconds
        : seconds;
    return DateTime.now().toUtc().add(Duration(seconds: boundedSeconds));
  }

  Future<void> _deleteManagedQueuedImage(String imagePath) async {
    try {
      final queueDir = await _ensurePendingScanDirectory();
      if (!imagePath.startsWith(queueDir)) return;
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup failures.
    }
  }

  Future<String> _ensurePendingScanDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final queueDir = Directory(
      '${appDir.path}${Platform.pathSeparator}pending_scans',
    );
    if (!await queueDir.exists()) {
      await queueDir.create(recursive: true);
    }
    return queueDir.path;
  }

  String? _metadataString(Map<String, dynamic>? metadata, String key) {
    final value = metadata?[key]?.toString().trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  int? _metadataInt(Map<String, dynamic>? metadata, String key) {
    final value = metadata?[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _metadataDouble(Map<String, dynamic>? metadata, String key) {
    final value = metadata?[key];
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  bool? _metadataBool(Map<String, dynamic>? metadata, String key) {
    final value = metadata?[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
      return true;
    }
    if (normalized == '0' || normalized == 'false' || normalized == 'no') {
      return false;
    }
    return null;
  }
}
