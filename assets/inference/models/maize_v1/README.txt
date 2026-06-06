Drop the trained TFLite model here as:

  assets/inference/models/maize_v1/model.tflite

Before registering this package in the app:
1. Train or export a maize model
2. Recompute manifest hashes:
   - model_sha256
   - labels_sha256
   - guidance_sha256
3. Validate the package with:
   python scripts\validate_offline_model_package.py --manifest assets/inference/models/maize_v1/manifest.json --dataset-root <dataset-root>

Current class target:
- Corn_(maize)___Cercospora_leaf_spot Gray_leaf_spot
- Corn_(maize)___Common_rust_
- Corn_(maize)___healthy
- Corn_(maize)___Northern_Leaf_Blight
