# IP102 Mobile Model Pipeline

This toolkit builds a separate insect/pest classifier for the Flutter `Pest Detection` tab. It does not reuse or modify the crop disease models.

## Python Requirement

Use Python 3.10 or 3.11. TensorFlow/TFLite tooling is not reliable on Python 3.14 yet.

```powershell
cd C:\Users\Admas\smart_farm
py -3.11 -m venv .venv-ip102
.\.venv-ip102\Scripts\Activate.ps1
pip install -r tools\ip102\requirements.txt
```

## Dataset Requirement

Download IP102 manually from the official project page/repository and extract it outside the Flutter asset tree, for example:

```text
C:\datasets\IP102
```

Expected dataset files vary by release. These scripts support the common IP102 layout with image folders plus train/val/test text files containing image path and class index.

## Recommended First Scope

Start with a crop-aligned subset instead of all 102 classes. For this project, `corn` is the safest first target because the app already supports maize/corn.

```powershell
python tools\ip102\prepare_subset.py `
  --dataset-root C:\datasets\IP102 `
  --output-root C:\datasets\IP102_mobile_subset `
  --class-name-contains corn
```

## Train

```powershell
python tools\ip102\train_classifier.py `
  --data-root C:\datasets\IP102_mobile_subset `
  --output-dir C:\models\ip102_v1 `
  --image-size 224 `
  --epochs 20
```

## Export TFLite

```powershell
python tools\ip102\export_tflite.py `
  --saved-model C:\models\ip102_v1\saved_model `
  --output-model C:\models\ip102_v1\model.tflite
```

## Package for Flutter

```powershell
python tools\ip102\package_flutter_bundle.py `
  --trained-dir C:\models\ip102_v1 `
  --flutter-root C:\Users\Admas\smart_farm `
  --bundle-name ip102_v1
```

After packaging, add these files to `pubspec.yaml` only when the model exists:

```yaml
- assets/inference/models/ip102_v1/model.tflite
- assets/inference/models/ip102_v1/labels.json
- assets/inference/models/ip102_v1/manifest.json
- assets/inference/models/ip102_v1/guidance.json
```

## Production Rule

The Flutter tab must continue to show `not installed` until the bundle is packaged and registered. Do not claim insect AI is active before that.
