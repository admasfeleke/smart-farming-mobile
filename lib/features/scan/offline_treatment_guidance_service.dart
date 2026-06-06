import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/disease_report_model.dart';
import 'offline_model_registry.dart';

class OfflineTreatmentGuidanceBundle {
  final String version;
  final Map<String, DiseaseTreatmentGuidance> byDiseaseLabel;

  const OfflineTreatmentGuidanceBundle({
    required this.version,
    required this.byDiseaseLabel,
  });
}

class OfflineTreatmentGuidanceService {
  OfflineTreatmentGuidanceService._();

  static final OfflineTreatmentGuidanceService instance =
      OfflineTreatmentGuidanceService._();

  static const String _defaultAssetPath =
      'assets/inference/models/plantvillage_v1/guidance.json';
  static const String _cacheFileName = 'offline_treatment_guide_cache.json';
  static final bool _isFlutterTestEnv =
      Platform.environment['FLUTTER_TEST'] == 'true';

  final Map<String, OfflineTreatmentGuidanceBundle> _cachedBundles =
      <String, OfflineTreatmentGuidanceBundle>{};
  final Set<String> _loadFailedAssets = <String>{};

  Future<DiseaseTreatmentGuidance?> guidanceForDiseaseLabel(
    String diseaseLabel,
    {String? cropName}
  ) async {
    final label = diseaseLabel.trim();
    if (label.isEmpty) return null;
    final bundle = await _ensureLoaded(cropName: cropName ?? diseaseLabel);
    if (bundle == null) return null;
    return bundle.byDiseaseLabel[label] ?? bundle.byDiseaseLabel[_fallbackKey];
  }

  static const String _fallbackKey = '__fallback__';

  Future<OfflineTreatmentGuidanceBundle?> _ensureLoaded({String? cropName}) async {
    await OfflineModelRegistry.instance.warmUp();
    final manifest = OfflineModelRegistry.instance.resolveManifestForCropName(cropName);
    final assetPath = (manifest.guidanceAsset ?? '').trim().isNotEmpty
        ? manifest.guidanceAsset!.trim()
        : _defaultAssetPath;
    if (_loadFailedAssets.contains(assetPath)) return null;
    final cachedBundle = _cachedBundles[assetPath];
    if (cachedBundle != null) return cachedBundle;
    try {
      final cached = await _tryLoadFromCacheFile(
        assetPath,
        expectedSha256: manifest.guidanceSha256,
      );
      if (cached != null) {
        _cachedBundles[assetPath] = cached;
        return cached;
      }

      final fromAsset = await _loadFromAsset(
        assetPath,
        expectedSha256: manifest.guidanceSha256,
      );
      _cachedBundles[assetPath] = fromAsset;
      return fromAsset;
    } catch (_) {
      _loadFailedAssets.add(assetPath);
      return null;
    }
  }

  Future<OfflineTreatmentGuidanceBundle?> _tryLoadFromCacheFile(
    String assetPath, {
    String? expectedSha256,
  }) async {
    if (_isFlutterTestEnv) {
      return null;
    }
    try {
      final file = await _cacheFile(assetPath);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (expectedSha256 != null && _sha256HexString(raw) != expectedSha256) {
        return null;
      }
      final bundle = _parseBundle(raw);
      return bundle;
    } catch (_) {
      return null;
    }
  }

  Future<OfflineTreatmentGuidanceBundle> _loadFromAsset(
    String assetPath, {
    String? expectedSha256,
  }) async {
    final raw = await rootBundle.loadString(assetPath);
    if (expectedSha256 != null && _sha256HexString(raw) != expectedSha256) {
      throw StateError('Offline guidance asset failed integrity validation.');
    }
    final bundle = _parseBundle(raw);
    return bundle ??
        const OfflineTreatmentGuidanceBundle(
          version: 'missing',
          byDiseaseLabel: <String, DiseaseTreatmentGuidance>{},
        );
  }

  OfflineTreatmentGuidanceBundle? _parseBundle(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final version = decoded['version']?.toString().trim();
      final byLabelRaw = decoded['by_label'];
      final byLabel = <String, DiseaseTreatmentGuidance>{};
      if (byLabelRaw is Map<String, dynamic>) {
        for (final entry in byLabelRaw.entries) {
          final key = entry.key.toString().trim();
          if (key.isEmpty) continue;
          final value = entry.value;
          if (value is Map<String, dynamic>) {
            byLabel[key] = DiseaseTreatmentGuidance.fromJson(value);
          }
        }
      }
      return OfflineTreatmentGuidanceBundle(
        version: (version == null || version.isEmpty) ? 'offline-guide-v1' : version,
        byDiseaseLabel: byLabel,
      );
    } catch (_) {
      return null;
    }
  }

  Future<File> _cacheFile(String assetPath) async {
    final dir = await getApplicationSupportDirectory();
    return File(
      '${dir.path}${Platform.pathSeparator}${_cacheFileNameForAsset(assetPath)}',
    );
  }

  String _cacheFileNameForAsset(String assetPath) {
    final normalized = assetPath.trim().toLowerCase();
    if (normalized.isEmpty) return _cacheFileName;
    final safe = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return '${safe}_$_cacheFileName';
  }

  /// Optional: store a new guide payload for offline use.
  /// You can call this after downloading a guide JSON from your backend.
  Future<bool> saveGuideJsonToCache(
    String rawJson, {
    String? assetPath,
    String? cropName,
  }) async {
    final parsed = _parseBundle(rawJson);
    if (parsed == null) return false;
    try {
      await OfflineModelRegistry.instance.warmUp();
      final resolvedAssetPath = (assetPath ?? '').trim().isNotEmpty
          ? assetPath!.trim()
          : ((OfflineModelRegistry.instance.resolveManifestForCropName(cropName).guidanceAsset ?? '')
                    .trim()
                    .isNotEmpty
                ? OfflineModelRegistry.instance
                    .resolveManifestForCropName(cropName)
                    .guidanceAsset!
                    .trim()
                : _defaultAssetPath);
      final file = await _cacheFile(resolvedAssetPath);
      await file.writeAsString(rawJson);
      _cachedBundles[resolvedAssetPath] = parsed;
      _loadFailedAssets.remove(resolvedAssetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  void clearMemoryCache() {
    _cachedBundles.clear();
    _loadFailedAssets.clear();
  }

  String _sha256HexString(String value) => sha256.convert(utf8.encode(value)).toString();

  @visibleForTesting
  static String get assetPathForTest => _defaultAssetPath;
}
