# IP102 Insect Detection Alignment

The Flutter pest detection tab is separate from crop disease scan. It must not reuse the PlantVillage disease model or submit insect results as disease reports.

## Expected Mobile Bundle

Place the converted model bundle at:

```text
assets/inference/models/ip102_v1/
```

Required files:

```text
manifest.json
model.tflite
labels.json
```

Optional file:

```text
guidance.json
```

## Manifest Contract

```json
{
  "model_id": "ip102-pest-v1",
  "model_version": "offline-tflite-v1",
  "dataset": "IP102",
  "task": "classification",
  "model_asset": "assets/inference/models/ip102_v1/model.tflite",
  "labels_asset": "assets/inference/models/ip102_v1/labels.json",
  "guidance_asset": "assets/inference/models/ip102_v1/guidance.json",
  "class_count": 102,
  "input_width": 224,
  "input_height": 224,
  "confidence_threshold": 0.70,
  "margin_threshold": 0.15
}
```

## Production Rule

Until this bundle exists and is validated, the app must show Pest Detection as not installed. This avoids confusing insect pest recognition with crop disease diagnosis.

## Next Implementation Steps

1. Train or obtain a mobile-suitable IP102 classifier.
2. Convert it to TFLite.
3. Add labels using IP102 class ordering.
4. Add an `InsectInferenceService`.
5. Add local pest history and a separate server pest-review workflow.
