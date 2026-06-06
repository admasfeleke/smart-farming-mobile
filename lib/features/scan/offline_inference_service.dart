import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../crop_scope.dart';
import '../../disease_naming.dart';
import 'offline_model_registry.dart';

class OfflineInferenceResult {
  final String diseaseName;
  final double confidenceScore;
  final String severity;
  final String modelId;
  final String modelVersion;
  final bool provisional;
  final List<OfflineInferenceScore> topScores;

  const OfflineInferenceResult({
    required this.diseaseName,
    required this.confidenceScore,
    required this.severity,
    required this.modelId,
    required this.modelVersion,
    this.provisional = true,
    this.topScores = const <OfflineInferenceScore>[],
  });

  String get canonicalDiseaseName => normalizeDiseaseKey(diseaseName);

  String get displayDiseaseName {
    final display = displayDiseaseLabel(diseaseName);
    return display.isEmpty ? diseaseName : display;
  }
}

class OfflineInferenceScore {
  final String label;
  final double score;

  const OfflineInferenceScore({required this.label, required this.score});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        'score': score,
      };
}

class OfflineInferenceReadiness {
  final bool ready;
  final String message;
  final String? modelId;
  final String? modelVersion;
  final String? modelAsset;
  final int? modelBytes;
  final String? labelsAsset;
  final int? labelsCount;

  const OfflineInferenceReadiness({
    required this.ready,
    required this.message,
    this.modelId,
    this.modelVersion,
    this.modelAsset,
    this.modelBytes,
    this.labelsAsset,
    this.labelsCount,
  });
}

class OfflineInferenceService {
  OfflineInferenceService._();

  static final OfflineInferenceService instance = OfflineInferenceService._();

  static const bool _enabled = bool.fromEnvironment(
    'SMART_FARM_ENABLE_OFFLINE_TFLITE',
    defaultValue: true,
  );
  static const int _minimumModelBytes = 4096;
  static const int _minimumLabelsCount = 2;

  Interpreter? _interpreter;
  List<String>? _labels;
  String? _loadedModelAsset;
  String? _loadedLabelsAsset;
  String? _lastLoadError;

  bool get isEnabled => _enabled;
  String? get unavailableReason => _lastLoadError;
  String get modelVersion =>
      OfflineModelRegistry.instance.activeManifest.modelVersion;
  String modelIdForCropName(String? cropName) => OfflineModelRegistry.instance
      .resolveManifestForCropName(cropName)
      .modelId;
  String modelVersionForCropName(String? cropName) => OfflineModelRegistry
      .instance
      .resolveManifestForCropName(cropName)
      .modelVersion;

  Future<void> prepareForCropName(String? cropName) async {
    await OfflineModelRegistry.instance.warmUp();
    final manifest = OfflineModelRegistry.instance.resolveManifestForCropName(
      cropName,
    );
    await _ensureLoaded(manifest);
  }

  Future<OfflineInferenceReadiness> checkReadiness({
    String? selectedCropName,
  }) async {
    await OfflineModelRegistry.instance.warmUp();
    final manifest = OfflineModelRegistry.instance.resolveManifestForCropName(
      selectedCropName,
    );
    if (!_enabled) {
      return const OfflineInferenceReadiness(
        ready: false,
        message: 'Offline inference is disabled by configuration.',
      );
    }

    final modelProbe = await _probeModelAsset(
      manifest.modelAsset,
      expectedSha256: manifest.modelSha256,
    );
    if (modelProbe == null) {
      return OfflineInferenceReadiness(
        ready: false,
        message: 'Offline model asset not found.',
        modelId: manifest.modelId,
        modelVersion: manifest.modelVersion,
        modelAsset: manifest.modelAsset,
      );
    }
    if (modelProbe.bytes < _minimumModelBytes) {
      return OfflineInferenceReadiness(
        ready: false,
        message:
            'Offline model asset appears empty or truncated (${modelProbe.bytes} bytes).',
        modelId: manifest.modelId,
        modelVersion: manifest.modelVersion,
        modelAsset: modelProbe.path,
        modelBytes: modelProbe.bytes,
      );
    }
    if (manifest.modelSha256 != null &&
        modelProbe.sha256 != manifest.modelSha256) {
      return OfflineInferenceReadiness(
        ready: false,
        message: 'Offline model asset failed integrity validation.',
        modelId: manifest.modelId,
        modelVersion: manifest.modelVersion,
        modelAsset: modelProbe.path,
        modelBytes: modelProbe.bytes,
      );
    }

    final labelsProbe = await _probeLabelsAsset(
      manifest.labelsAsset,
      expectedSha256: manifest.labelsSha256,
    );
    if (labelsProbe == null) {
      return OfflineInferenceReadiness(
        ready: false,
        message: 'Offline labels asset is missing or empty.',
        modelId: manifest.modelId,
        modelVersion: manifest.modelVersion,
        modelAsset: modelProbe.path,
        modelBytes: modelProbe.bytes,
      );
    }
    if (labelsProbe.labels.length < _minimumLabelsCount) {
      return OfflineInferenceReadiness(
        ready: false,
        message:
            'Offline labels asset has too few classes (${labelsProbe.labels.length}).',
        modelId: manifest.modelId,
        modelVersion: manifest.modelVersion,
        modelAsset: modelProbe.path,
        modelBytes: modelProbe.bytes,
        labelsAsset: labelsProbe.path,
        labelsCount: labelsProbe.labels.length,
      );
    }
    if (manifest.labelsSha256 != null &&
        labelsProbe.sha256 != manifest.labelsSha256) {
      return OfflineInferenceReadiness(
        ready: false,
        message: 'Offline labels asset failed integrity validation.',
        modelId: manifest.modelId,
        modelVersion: manifest.modelVersion,
        modelAsset: modelProbe.path,
        modelBytes: modelProbe.bytes,
        labelsAsset: labelsProbe.path,
        labelsCount: labelsProbe.labels.length,
      );
    }

    return OfflineInferenceReadiness(
      ready: true,
      message: 'Offline inference assets are ready.',
      modelId: manifest.modelId,
      modelVersion: manifest.modelVersion,
      modelAsset: modelProbe.path,
      modelBytes: modelProbe.bytes,
      labelsAsset: labelsProbe.path,
      labelsCount: labelsProbe.labels.length,
    );
  }

  Future<OfflineInferenceResult?> inferFromImagePath({
    required String imagePath,
    String? selectedCropName,
  }) async {
    await OfflineModelRegistry.instance.warmUp();
    final manifest = OfflineModelRegistry.instance.resolveManifestForCropName(
      selectedCropName,
    );
    if (!_enabled) {
      return null;
    }
    final file = File(imagePath);
    if (!await file.exists()) {
      _lastLoadError = 'Captured image is missing.';
      return null;
    }

    final ready = await _ensureLoaded(manifest);
    if (!ready) {
      return null;
    }

    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      _lastLoadError = 'Captured image could not be decoded.';
      return null;
    }
    final interpreter = _interpreter;
    final labels = _labels;
    if (interpreter == null || labels == null || labels.isEmpty) {
      _lastLoadError = 'Offline model is not initialized.';
      return null;
    }

    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final inputShape = inputTensor.shape;
    final outputShape = outputTensor.shape;
    if (inputShape.length != 4 || outputShape.length < 2) {
      _lastLoadError = 'Offline model tensor shape is not supported.';
      return null;
    }
    final height = inputShape[1];
    final width = inputShape[2];
    final channels = inputShape[3];
    if (height <= 0 || width <= 0 || channels != 3) {
      _lastLoadError = 'Offline model input shape is invalid.';
      return null;
    }
    if (manifest.inputWidth > 0 &&
        manifest.inputHeight > 0 &&
        (manifest.inputWidth != width || manifest.inputHeight != height)) {
      _lastLoadError =
          'Offline model manifest does not match model input shape.';
      return null;
    }
    final resized = img.copyResize(
      decoded,
      width: width,
      height: height,
      interpolation: img.Interpolation.cubic,
    );
    final screening = _screenImageForOfflineInference(resized, manifest);
    if (!screening.passed) {
      _lastLoadError = screening.reason ?? 'Offline image quality is too low.';
      return null;
    }

    final input = _buildInput(
      image: resized,
      tensorType: inputTensor.type,
      width: width,
      height: height,
      manifest: manifest,
    );
    if (outputShape.length != 2 || outputShape.first != 1) {
      _lastLoadError = 'Offline model output shape is invalid.';
      return null;
    }
    // Ensure the model output matches the labels list length.
    // If this mismatches, predictions cannot be mapped reliably.
    if (outputShape.last != labels.length) {
      _lastLoadError = 'Offline model labels do not match output classes.';
      return null;
    }
    final output = List<List<double>>.generate(
      1,
      (_) => List<double>.filled(outputShape.last, 0),
    );

    try {
      interpreter.run(input, output);
    } catch (_) {
      _lastLoadError = 'Offline model inference failed.';
      return null;
    }

    final rawScores = output.first;
    final scores = manifest.outputType == OfflineModelOutputType.logits
        ? _softmax(rawScores)
        : rawScores;
    if (scores.isEmpty) {
      _lastLoadError = 'Offline model returned no scores.';
      return null;
    }
    var bestIdx = 0;
    var bestScore = scores[0];
    var secondBestScore = scores.length > 1 ? scores[1] : 0.0;
    if (secondBestScore > bestScore) {
      final swap = bestScore;
      bestScore = secondBestScore;
      secondBestScore = swap;
      bestIdx = 1;
    }
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > bestScore) {
        secondBestScore = bestScore;
        bestScore = scores[i];
        bestIdx = i;
      } else if (scores[i] > secondBestScore && i != bestIdx) {
        secondBestScore = scores[i];
      }
    }
    if (bestIdx < 0 || bestIdx >= labels.length) {
      _lastLoadError = 'Offline prediction index is out of range.';
      return null;
    }

    final confidence = bestScore.clamp(0.0, 1.0);
    final margin = (bestScore - secondBestScore).clamp(0.0, 1.0);
    final diseaseName = labels[bestIdx];
    final topScores = <OfflineInferenceScore>[];
    for (var i = 0; i < scores.length && i < labels.length; i++) {
      topScores.add(
        OfflineInferenceScore(
          label: labels[i],
          score: scores[i].clamp(0.0, 1.0),
        ),
      );
    }
    topScores.sort((a, b) => b.score.compareTo(a.score));
    final predictedFamily = cropFamilyFromName(diseaseName);
    final selectedFamily = cropFamilyFromName(selectedCropName);
    if (predictedFamily == null ||
        !manifest.supportedCropFamilies.contains(predictedFamily)) {
      _lastLoadError = 'Offline prediction is outside the active model scope.';
      return null;
    }
    if (selectedFamily != null && selectedFamily != predictedFamily) {
      _lastLoadError =
          'Offline prediction does not match the selected crop family.';
      return null;
    }
    if (confidence < manifest.confidenceThreshold) {
      _lastLoadError =
          'Offline confidence is too low for a trustworthy result.';
      return null;
    }
    if (labels.length > 1 && margin < manifest.marginThreshold) {
      _lastLoadError = 'Offline prediction is too ambiguous. Retake the photo.';
      return null;
    }
    final severity = _severityFromPrediction(diseaseName, manifest);
    _lastLoadError = null;
    return OfflineInferenceResult(
      diseaseName: diseaseName,
      confidenceScore: confidence,
      severity: severity,
      modelId: manifest.modelId,
      modelVersion: manifest.modelVersion,
      provisional: true,
      topScores: topScores.take(3).toList(growable: false),
    );
  }

  Future<bool> _ensureLoaded(OfflineModelManifest manifest) async {
    if (_interpreter != null &&
        _labels != null &&
        _labels!.isNotEmpty &&
        _loadedModelAsset == manifest.modelAsset &&
        _loadedLabelsAsset == manifest.labelsAsset) {
      return true;
    }
    if (_loadedModelAsset != manifest.modelAsset ||
        _loadedLabelsAsset != manifest.labelsAsset) {
      _interpreter?.close();
      _interpreter = null;
      _labels = null;
      _loadedModelAsset = null;
      _loadedLabelsAsset = null;
    }

    final modelProbe = await _probeModelAsset(
      manifest.modelAsset,
      expectedSha256: manifest.modelSha256,
    );
    if (modelProbe == null) {
      _lastLoadError = 'Offline model asset not found.';
      return false;
    }
    if (modelProbe.bytes < _minimumModelBytes) {
      _lastLoadError =
          'Offline model asset appears empty or truncated (${modelProbe.bytes} bytes).';
      return false;
    }
    if (manifest.modelSha256 != null &&
        modelProbe.sha256 != manifest.modelSha256) {
      _lastLoadError = 'Offline model asset failed integrity validation.';
      return false;
    }

    final labelsProbe = await _probeLabelsAsset(
      manifest.labelsAsset,
      expectedSha256: manifest.labelsSha256,
    );
    if (labelsProbe == null) {
      _lastLoadError = 'Offline labels asset is missing or empty.';
      return false;
    }
    if (labelsProbe.labels.length < _minimumLabelsCount) {
      _lastLoadError =
          'Offline labels asset has too few classes (${labelsProbe.labels.length}).';
      return false;
    }
    if (manifest.labelsSha256 != null &&
        labelsProbe.sha256 != manifest.labelsSha256) {
      _lastLoadError = 'Offline labels asset failed integrity validation.';
      return false;
    }
    if (manifest.classCount > 0 &&
        labelsProbe.labels.length != manifest.classCount) {
      _lastLoadError =
          'Offline manifest class count does not match labels asset.';
      return false;
    }
    final modelAssetUsed = manifest.modelAsset;
    final labelsAssetUsed = manifest.labelsAsset;
    final loadedLabels = labelsProbe.labels;

    try {
      _interpreter = await Interpreter.fromAsset(modelAssetUsed);
      _labels = loadedLabels;
      _loadedModelAsset = modelAssetUsed;
      _loadedLabelsAsset = labelsAssetUsed;
      _lastLoadError = null;
      return true;
    } catch (_) {
      _lastLoadError = 'Failed to initialize offline model: $modelAssetUsed';
      return false;
    }
  }

  Future<_ModelAssetProbe?> _probeModelAsset(
    String assetPath, {
    String? expectedSha256,
  }) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      final sha256Hex = _sha256HexBytes(bytes);
      if (expectedSha256 != null && sha256Hex != expectedSha256) {
        return _ModelAssetProbe(assetPath, data.lengthInBytes, sha256Hex);
      }
      return _ModelAssetProbe(assetPath, data.lengthInBytes, sha256Hex);
    } catch (_) {
      return null;
    }
  }

  Future<_LabelsAssetProbe?> _probeLabelsAsset(
    String assetPath, {
    String? expectedSha256,
  }) async {
    final raw = await _loadLabelsRaw(assetPath);
    if (raw == null) {
      return null;
    }
    final sha256Hex = _sha256HexString(raw);
    if (expectedSha256 != null && sha256Hex != expectedSha256) {
      return _LabelsAssetProbe(assetPath, const <String>[], sha256Hex);
    }
    final preferred = _parseLabels(raw);
    if (preferred.isNotEmpty) {
      return _LabelsAssetProbe(assetPath, preferred, sha256Hex);
    }
    return null;
  }

  Future<String?> _loadLabelsRaw(String assetPath) async {
    try {
      return await rootBundle.loadString(assetPath);
    } catch (_) {
      return null;
    }
  }

  List<String> _parseLabels(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <String>[];
      }
      return decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Object _buildInput({
    required img.Image image,
    required TensorType tensorType,
    required int width,
    required int height,
    required OfflineModelManifest manifest,
  }) {
    if (tensorType == TensorType.float32) {
      final input = List.generate(
        1,
        (_) => List.generate(
          height,
          (_) => List.generate(width, (_) => List<double>.filled(3, 0)),
        ),
      );
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final channels = _pixelChannels(
            image.getPixel(x, y),
            manifest.colorOrder,
          );
          input[0][y][x][0] = _normalizeChannel(
            channels[0],
            scale: manifest.inputScale,
            mean: manifest.inputMean[0],
            std: manifest.inputStd[0],
          );
          input[0][y][x][1] = _normalizeChannel(
            channels[1],
            scale: manifest.inputScale,
            mean: manifest.inputMean[1],
            std: manifest.inputStd[1],
          );
          input[0][y][x][2] = _normalizeChannel(
            channels[2],
            scale: manifest.inputScale,
            mean: manifest.inputMean[2],
            std: manifest.inputStd[2],
          );
        }
      }
      return input;
    }

    final input = List.generate(
      1,
      (_) => List.generate(
        height,
        (_) => List.generate(width, (_) => List<int>.filled(3, 0)),
      ),
    );
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final channels = _pixelChannels(
          image.getPixel(x, y),
          manifest.colorOrder,
        );
        input[0][y][x][0] = channels[0].clamp(0, 255).toInt();
        input[0][y][x][1] = channels[1].clamp(0, 255).toInt();
        input[0][y][x][2] = channels[2].clamp(0, 255).toInt();
      }
    }
    return input;
  }

  double _normalizeChannel(
    num value, {
    required double scale,
    required double mean,
    required double std,
  }) {
    final safeStd = std == 0 ? 1.0 : std;
    return ((value.toDouble() * scale) - mean) / safeStd;
  }

  List<int> _pixelChannels(img.Pixel pixel, OfflineModelColorOrder colorOrder) {
    switch (colorOrder) {
      case OfflineModelColorOrder.bgr:
        return <int>[pixel.b.toInt(), pixel.g.toInt(), pixel.r.toInt()];
      case OfflineModelColorOrder.rgb:
        return <int>[pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
    }
  }

  List<double> _softmax(List<double> logits) {
    if (logits.isEmpty) return const <double>[];
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits
        .map((value) => math.exp(value - maxLogit))
        .toList(growable: false);
    final sum = exps.fold<double>(0.0, (total, value) => total + value);
    if (sum <= 0) {
      return List<double>.filled(logits.length, 0.0, growable: false);
    }
    return exps.map((value) => value / sum).toList(growable: false);
  }

  _OfflineImageScreening _screenImageForOfflineInference(
    img.Image image,
    OfflineModelManifest manifest,
  ) {
    final step = math.max(1, math.min(image.width, image.height) ~/ 96);
    var sampleCount = 0;
    var leafLikeCount = 0;
    var centerSampleCount = 0;
    var centerLeafLikeCount = 0;
    var edgeCount = 0;
    double luminanceSum = 0;
    double luminanceSquaredSum = 0;
    final centerLeft = image.width * 0.2;
    final centerRight = image.width * 0.8;
    final centerTop = image.height * 0.2;
    final centerBottom = image.height * 0.8;

    for (var y = 0; y < image.height; y += step) {
      double? previousLuminance;
      for (var x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        final luminance = (0.299 * r) + (0.587 * g) + (0.114 * b);
        luminanceSum += luminance;
        luminanceSquaredSum += luminance * luminance;
        sampleCount += 1;
        final leafLike = _looksLeafLike(r, g, b);
        if (leafLike) {
          leafLikeCount += 1;
        }
        final withinCenter =
            x >= centerLeft &&
            x <= centerRight &&
            y >= centerTop &&
            y <= centerBottom;
        if (withinCenter) {
          centerSampleCount += 1;
          if (leafLike) {
            centerLeafLikeCount += 1;
          }
        }
        if (previousLuminance != null &&
            (luminance - previousLuminance).abs() > 18.0) {
          edgeCount += 1;
        }
        previousLuminance = luminance;
      }
    }

    if (sampleCount == 0) {
      return const _OfflineImageScreening(
        passed: false,
        reason: 'Offline photo quality could not be checked.',
      );
    }

    final mean = luminanceSum / sampleCount;
    final variance = (luminanceSquaredSum / sampleCount) - (mean * mean);
    final stdDev = math.sqrt(variance < 0 ? 0 : variance);
    final leafLikeRatio = leafLikeCount / sampleCount;
    final centerLeafLikeRatio = centerSampleCount == 0
        ? 0.0
        : centerLeafLikeCount / centerSampleCount;
    final edgeRatio = edgeCount / sampleCount;
    final minLeafLikeRatio = math.max(manifest.minLeafLikeRatio, 0.10);
    final minCenterLeafLikeRatio = math.max(minLeafLikeRatio, 0.14);
    final minEdgeRatio = math.max(manifest.minEdgeRatio, 0.02);

    if (leafLikeRatio < minLeafLikeRatio) {
      return const _OfflineImageScreening(
        passed: false,
        reason:
            'Offline photo does not appear to contain enough crop leaf area.',
      );
    }
    if (centerLeafLikeRatio < minCenterLeafLikeRatio) {
      return const _OfflineImageScreening(
        passed: false,
        reason: 'Center the crop leaf clearly before scanning.',
      );
    }
    if (stdDev < manifest.minLuminanceStdDev || edgeRatio < minEdgeRatio) {
      return const _OfflineImageScreening(
        passed: false,
        reason:
            'Offline photo is too blurry, flat, or unclear for a safe result.',
      );
    }
    return _OfflineImageScreening(
      passed: true,
      leafLikeRatio: leafLikeRatio,
      luminanceStdDev: stdDev,
      edgeRatio: edgeRatio,
    );
  }

  bool _looksLeafLike(double r, double g, double b) {
    final maxChannel = math.max(r, math.max(g, b));
    final minChannel = math.min(r, math.min(g, b));
    final spread = maxChannel - minChannel;
    if (maxChannel < 35) return false;
    if (spread < 18) return false;
    final greenish = g >= (b * 1.05) && g >= (r * 0.85);
    final yellowish = r > 85 && g > 75 && b < (g * 0.85) && (r - g).abs() < 70;
    final brownLeaf = r > 75 && g > 50 && b < 110 && r >= g && g >= (b * 0.85);
    return greenish || yellowish || brownLeaf;
  }

  String _sha256HexBytes(List<int> bytes) => sha256.convert(bytes).toString();

  String _sha256HexString(String value) => _sha256HexBytes(utf8.encode(value));

  String _severityFromPrediction(
    String diseaseName,
    OfflineModelManifest manifest,
  ) {
    final mapped = manifest.severityByLabel[diseaseName]?.trim().toLowerCase();
    if (mapped == 'low' || mapped == 'medium' || mapped == 'high') {
      return mapped!;
    }
    final lower = diseaseName.toLowerCase();
    if (lower.contains('healthy')) {
      return 'low';
    }
    if (lower.contains('late_blight') || lower.contains('mosaic_virus')) {
      return 'high';
    }
    return 'medium';
  }
}

class _ModelAssetProbe {
  final String path;
  final int bytes;
  final String sha256;
  const _ModelAssetProbe(this.path, this.bytes, this.sha256);
}

class _LabelsAssetProbe {
  final String path;
  final List<String> labels;
  final String sha256;
  const _LabelsAssetProbe(this.path, this.labels, this.sha256);
}

class _OfflineImageScreening {
  final bool passed;
  final String? reason;
  final double? leafLikeRatio;
  final double? luminanceStdDev;
  final double? edgeRatio;

  const _OfflineImageScreening({
    required this.passed,
    this.reason,
    this.leafLikeRatio,
    this.luminanceStdDev,
    this.edgeRatio,
  });
}
