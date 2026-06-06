Drop the trained TensorFlow Lite file here as:
model.tflite

This package is not registered in pubspec.yaml yet because the model file does not
exist. Register these assets only after model.tflite is added:

- assets/inference/models/tomato_v1/model.tflite
- assets/inference/models/tomato_v1/labels.json
- assets/inference/models/tomato_v1/guidance.json
- assets/inference/models/tomato_v1/manifest.json

After that, add the manifest path to:
lib/features/scan/offline_model_registry.dart
