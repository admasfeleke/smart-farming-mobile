import 'dart:convert';
import 'dart:io';

void main() {
  const modelCandidates = <String>[
    'assets/inference/expert_model_plantvillage.tflite',
    'assets/inference/expert_model.tflite',
  ];
  const labelsCandidates = <String>[
    'assets/inference/labels_plantvillage.json',
    'assets/inference/labels_38.json',
  ];
  const minModelBytes = 4096;
  const minLabelsCount = 2;

  final model = _firstExisting(modelCandidates);
  if (model == null) {
    _fail('No offline model asset found.', modelCandidates);
  }

  final modelBytes = model.lengthSync();
  if (modelBytes < minModelBytes) {
    _fail(
      'Offline model looks invalid: ${model.path} is only $modelBytes bytes.',
      modelCandidates,
    );
  }

  final labels = _firstExisting(labelsCandidates);
  if (labels == null) {
    _fail('No offline labels asset found.', labelsCandidates);
  }

  final labelsCount = _labelsCount(labels);
  if (labelsCount < minLabelsCount) {
    _fail(
      'Offline labels look invalid: ${labels.path} has $labelsCount labels.',
      labelsCandidates,
    );
  }

  stdout.writeln('PASS');
  stdout.writeln('model: ${model.path} ($modelBytes bytes)');
  stdout.writeln('labels: ${labels.path} ($labelsCount classes)');
}

File? _firstExisting(List<String> candidates) {
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  return null;
}

int _labelsCount(File file) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is List) {
      return decoded.where((e) => e.toString().trim().isNotEmpty).length;
    }
    return 0;
  } catch (_) {
    return 0;
  }
}

Never _fail(String message, List<String> candidates) {
  stderr.writeln('FAIL: $message');
  stderr.writeln('Checked candidates:');
  for (final c in candidates) {
    stderr.writeln(' - $c');
  }
  exit(1);
}
