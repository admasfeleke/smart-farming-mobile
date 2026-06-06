import 'dart:convert';

import 'package:flutter/services.dart';

class InsectModelManifest {
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
  final String dataset;
  final String task;

  const InsectModelManifest({
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
    required this.dataset,
    required this.task,
  });

  factory InsectModelManifest.fromJson(Map<String, dynamic> json) {
    return InsectModelManifest(
      modelId: _text(json['model_id'], fallback: 'ip102-pest-v1'),
      modelVersion: _text(json['model_version'], fallback: 'offline-tflite-v1'),
      modelAsset: _text(
        json['model_asset'],
        fallback: 'assets/inference/models/ip102_v1/model.tflite',
      ),
      labelsAsset: _text(
        json['labels_asset'],
        fallback: 'assets/inference/models/ip102_v1/labels.json',
      ),
      guidanceAsset: _optionalText(json['guidance_asset']),
      classCount: _int(json['class_count'], fallback: 102),
      inputWidth: _int(json['input_width'], fallback: 224),
      inputHeight: _int(json['input_height'], fallback: 224),
      confidenceThreshold: _double(json['confidence_threshold'], fallback: 0.70),
      marginThreshold: _double(json['margin_threshold'], fallback: 0.15),
      dataset: _text(json['dataset'], fallback: 'IP102'),
      task: _text(json['task'], fallback: 'classification'),
    );
  }

  static String _text(Object? value, {required String fallback}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _optionalText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int _int(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _double(Object? value, {required double fallback}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class InsectModelRegistry {
  InsectModelRegistry._();

  static final InsectModelRegistry instance = InsectModelRegistry._();
  static const String manifestAsset =
      'assets/inference/models/ip102_v1/manifest.json';

  bool _loaded = false;
  InsectModelManifest? _manifest;
  String? _loadError;

  bool get isLoaded => _loaded;
  bool get isInstalled => _manifest != null;
  InsectModelManifest? get manifest => _manifest;
  String? get loadError => _loadError;

  Future<void> warmUp() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString(manifestAsset);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid IP102 manifest format.');
      }
      final manifest = InsectModelManifest.fromJson(decoded);
      await rootBundle.load(manifest.modelAsset);
      await rootBundle.loadString(manifest.labelsAsset);
      _manifest = manifest;
      _loadError = null;
    } catch (e) {
      _manifest = null;
      _loadError = e.toString();
    } finally {
      _loaded = true;
    }
  }
}
