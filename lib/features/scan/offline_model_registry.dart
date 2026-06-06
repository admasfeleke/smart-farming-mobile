import 'dart:convert';

import 'package:flutter/services.dart';

import '../../crop_scope.dart';

enum OfflineModelColorOrder { rgb, bgr }

enum OfflineModelOutputType { probabilities, logits }

class OfflineModelManifest {
  final String modelId;
  final String modelVersion;
  final String modelAsset;
  final String labelsAsset;
  final String? guidanceAsset;
  final int classCount;
  final int inputWidth;
  final int inputHeight;
  final double confidenceThreshold;
  final double marginThreshold;
  final List<String> supportedCropFamilies;
  final Map<String, String> severityByLabel;
  final double inputScale;
  final List<double> inputMean;
  final List<double> inputStd;
  final OfflineModelColorOrder colorOrder;
  final OfflineModelOutputType outputType;
  final double minLeafLikeRatio;
  final double minLuminanceStdDev;
  final double minEdgeRatio;
  final String? modelSha256;
  final String? labelsSha256;
  final String? guidanceSha256;

  const OfflineModelManifest({
    required this.modelId,
    required this.modelVersion,
    required this.modelAsset,
    required this.labelsAsset,
    required this.guidanceAsset,
    required this.classCount,
    required this.inputWidth,
    required this.inputHeight,
    required this.confidenceThreshold,
    required this.marginThreshold,
    required this.supportedCropFamilies,
    required this.severityByLabel,
    required this.inputScale,
    required this.inputMean,
    required this.inputStd,
    required this.colorOrder,
    required this.outputType,
    required this.minLeafLikeRatio,
    required this.minLuminanceStdDev,
    required this.minEdgeRatio,
    required this.modelSha256,
    required this.labelsSha256,
    required this.guidanceSha256,
  });

  factory OfflineModelManifest.fromJson(Map<String, dynamic> json) {
    final cropFamilies =
        (json['supported_crop_families'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e.toString().trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList();
    final severityByLabel = <String, String>{};
    final rawSeverity = json['severity_by_label'];
    if (rawSeverity is Map) {
      for (final entry in rawSeverity.entries) {
        final key = entry.key.toString().trim();
        final rawValue = entry.value?.toString() ?? '';
        final value = rawValue.trim().toLowerCase();
        if (key.isEmpty || value.isEmpty) continue;
        severityByLabel[key] = value;
      }
    }

    final modelId = (json['model_id']?.toString() ?? '').trim();
    final modelVersion = (json['model_version']?.toString() ?? '').trim();
    final modelAsset = (json['model_asset']?.toString() ?? '').trim();
    final labelsAsset = (json['labels_asset']?.toString() ?? '').trim();
    final guidanceAssetText = (json['guidance_asset']?.toString() ?? '').trim();
    final modelSha256 = _normalizedHash(json['model_sha256']);
    final labelsSha256 = _normalizedHash(json['labels_sha256']);
    final guidanceSha256 = _normalizedHash(json['guidance_sha256']);
    final inputMean = _toChannelTriplet(json['input_mean'], fallback: 0.0);
    final inputStd = _toChannelTriplet(
      json['input_std'],
      fallback: 1.0,
      allowZero: false,
    );

    return OfflineModelManifest(
      modelId: modelId.isNotEmpty
          ? modelId
          : 'plantvillage-central-ethiopia-v1',
      modelVersion: modelVersion.isNotEmpty
          ? modelVersion
          : 'offline-tflite-v1',
      modelAsset: modelAsset.isNotEmpty
          ? modelAsset
          : 'assets/inference/models/plantvillage_v1/model.tflite',
      labelsAsset: labelsAsset.isNotEmpty
          ? labelsAsset
          : 'assets/inference/models/plantvillage_v1/labels.json',
      guidanceAsset: guidanceAssetText.isEmpty ? null : guidanceAssetText,
      classCount: _toInt(json['class_count'], fallback: 15),
      inputWidth: _toInt(json['input_width'], fallback: 224),
      inputHeight: _toInt(json['input_height'], fallback: 224),
      confidenceThreshold: _toDouble(
        json['confidence_threshold'],
        fallback: 0.72,
      ),
      marginThreshold: _toDouble(json['margin_threshold'], fallback: 0.18),
      supportedCropFamilies: cropFamilies.isEmpty
          ? kDefaultSupportedCropFamilies.toList(growable: false)
          : cropFamilies,
      severityByLabel: severityByLabel,
      inputScale: _toDouble(json['input_scale'], fallback: 1.0 / 255.0),
      inputMean: inputMean,
      inputStd: inputStd,
      colorOrder: _parseColorOrder(json['color_order']),
      outputType: _parseOutputType(json['output_type']),
      minLeafLikeRatio: _toDouble(json['min_leaf_like_ratio'], fallback: 0.05),
      minLuminanceStdDev: _toDouble(
        json['min_luminance_stddev'],
        fallback: 12.0,
      ),
      minEdgeRatio: _toDouble(json['min_edge_ratio'], fallback: 0.015),
      modelSha256: modelSha256,
      labelsSha256: labelsSha256,
      guidanceSha256: guidanceSha256,
    );
  }

  static int _toInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _toDouble(Object? value, {required double fallback}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static List<double> _toChannelTriplet(
    Object? value, {
    required double fallback,
    bool allowZero = true,
  }) {
    if (value is List && value.length >= 3) {
      final parsed = value
          .take(3)
          .map((entry) => _toDouble(entry, fallback: fallback))
          .map((entry) => !allowZero && entry == 0 ? fallback : entry)
          .toList(growable: false);
      if (parsed.length == 3) {
        return parsed;
      }
    }
    return List<double>.filled(3, fallback, growable: false);
  }

  static OfflineModelColorOrder _parseColorOrder(Object? raw) {
    switch ((raw?.toString() ?? '').trim().toLowerCase()) {
      case 'bgr':
        return OfflineModelColorOrder.bgr;
      case 'rgb':
      default:
        return OfflineModelColorOrder.rgb;
    }
  }

  static OfflineModelOutputType _parseOutputType(Object? raw) {
    switch ((raw?.toString() ?? '').trim().toLowerCase()) {
      case 'logits':
        return OfflineModelOutputType.logits;
      case 'probabilities':
      default:
        return OfflineModelOutputType.probabilities;
    }
  }

  static String? _normalizedHash(Object? raw) {
    final value = (raw?.toString() ?? '').trim().toLowerCase();
    if (value.length != 64) return null;
    final hashPattern = RegExp(r'^[0-9a-f]{64}$');
    return hashPattern.hasMatch(value) ? value : null;
  }
}

class OfflineModelRegistry {
  OfflineModelRegistry._();

  static final OfflineModelRegistry instance = OfflineModelRegistry._();

  static const List<String> _manifestAssets = <String>[
    'assets/inference/models/tomato_v1/manifest.json',
    'assets/inference/models/potato_v1/manifest.json',
    'assets/inference/models/pepper_v1/manifest.json',
    'assets/inference/models/maize_v1/manifest.json',
  ];

  static const OfflineModelManifest _fallbackManifest = OfflineModelManifest(
    modelId: 'tomato-efficientnet-v1',
    modelVersion: 'tomato-offline-tflite-v1',
    modelAsset: 'assets/inference/models/tomato_v1/model.tflite',
    labelsAsset: 'assets/inference/models/tomato_v1/labels.json',
    guidanceAsset: 'assets/inference/models/tomato_v1/guidance.json',
    classCount: 10,
    inputWidth: 160,
    inputHeight: 160,
    confidenceThreshold: 0.75,
    marginThreshold: 0.12,
    supportedCropFamilies: <String>['tomato'],
    severityByLabel: <String, String>{
      'Pepper__bell___Bacterial_spot': 'medium',
      'Pepper__bell___healthy': 'low',
      'Potato___Early_blight': 'high',
      'Potato___Late_blight': 'high',
      'Potato___healthy': 'low',
      'Tomato_Bacterial_spot': 'medium',
      'Tomato_Early_blight': 'medium',
      'Tomato_Late_blight': 'high',
      'Tomato_Leaf_Mold': 'medium',
      'Tomato_Septoria_leaf_spot': 'medium',
      'Tomato_Spider_mites_Two_spotted_spider_mite': 'medium',
      'Tomato__Target_Spot': 'medium',
      'Tomato__Tomato_YellowLeaf__Curl_Virus': 'high',
      'Tomato__Tomato_mosaic_virus': 'high',
      'Tomato_healthy': 'low',
    },
    inputScale: 1.0 / 255.0,
    inputMean: <double>[0.0, 0.0, 0.0],
    inputStd: <double>[1.0, 1.0, 1.0],
    colorOrder: OfflineModelColorOrder.rgb,
    outputType: OfflineModelOutputType.probabilities,
    minLeafLikeRatio: 0.05,
    minLuminanceStdDev: 12.0,
    minEdgeRatio: 0.015,
    modelSha256: null,
    labelsSha256: null,
    guidanceSha256: null,
  );

  OfflineModelManifest _activeManifest = _fallbackManifest;
  List<OfflineModelManifest> _availableManifests =
      const <OfflineModelManifest>[];
  bool _loaded = false;

  OfflineModelManifest get activeManifest => _activeManifest;
  List<OfflineModelManifest> get availableManifests =>
      List<OfflineModelManifest>.unmodifiable(_availableManifests);
  List<String> get supportedCropFamilies {
    final families = <String>{};
    for (final manifest in _availableManifests) {
      families.addAll(manifest.supportedCropFamilies);
    }
    if (families.isEmpty) {
      families.addAll(_activeManifest.supportedCropFamilies);
    }
    final sorted = families.toList()..sort();
    return List<String>.unmodifiable(sorted);
  }

  bool get isLoaded => _loaded;

  OfflineModelManifest resolveManifestForCropFamily(String? cropFamily) {
    final normalized = cropFamily?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return _activeManifest;
    }
    final matches = _availableManifests
        .where(
          (manifest) => manifest.supportedCropFamilies.contains(normalized),
        )
        .toList();
    if (matches.isNotEmpty) {
      matches.sort(
        (a, b) => a.supportedCropFamilies.length.compareTo(
          b.supportedCropFamilies.length,
        ),
      );
      return matches.first;
    }
    return _activeManifest;
  }

  OfflineModelManifest resolveManifestForCropName(String? cropName) {
    return resolveManifestForCropFamily(cropFamilyFromName(cropName));
  }

  Future<void> warmUp() async {
    if (_loaded) return;
    final manifests = <OfflineModelManifest>[];
    try {
      for (final asset in _manifestAssets) {
        try {
          final raw = await rootBundle.loadString(asset);
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            manifests.add(OfflineModelManifest.fromJson(decoded));
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      // Fall through to fallback manifest below.
    } finally {
      if (manifests.isEmpty) {
        manifests.add(_fallbackManifest);
      }
      _availableManifests = List<OfflineModelManifest>.unmodifiable(manifests);
      _activeManifest = _availableManifests.first;
      updateSupportedCropFamilies(supportedCropFamilies);
      _loaded = true;
    }
  }
}
