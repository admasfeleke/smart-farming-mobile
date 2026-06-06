Drop the trained TFLite model here as:

  assets/inference/models/pepper_v1/model.tflite

Before registering this package in pubspec/registry:
1. Generate or update model.tflite
2. Recompute manifest hashes:
   - model_sha256
   - labels_sha256
   - guidance_sha256
3. Validate the package with:
   python scripts\validate_offline_model_package.py --manifest assets/inference/models/pepper_v1/manifest.json --dataset-root <dataset-root>

Suggested classes:
- Pepper__bell___Bacterial_spot
- Pepper__bell___healthy
