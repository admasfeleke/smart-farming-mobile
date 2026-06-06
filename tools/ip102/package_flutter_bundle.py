from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from common import write_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Package trained IP102 model for Flutter.")
    parser.add_argument("--trained-dir", required=True, type=Path)
    parser.add_argument("--flutter-root", required=True, type=Path)
    parser.add_argument("--bundle-name", default="ip102_v1")
    parser.add_argument("--image-size", default=224, type=int)
    parser.add_argument("--confidence-threshold", default=0.70, type=float)
    parser.add_argument("--margin-threshold", default=0.15, type=float)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    target = args.flutter_root / "assets" / "inference" / "models" / args.bundle_name
    target.mkdir(parents=True, exist_ok=True)

    model = args.trained_dir / "model.tflite"
    labels = args.trained_dir / "labels.json"
    metrics = args.trained_dir / "metrics.json"
    if not model.exists():
        raise SystemExit(f"Missing {model}. Run export_tflite.py first.")
    if not labels.exists():
        raise SystemExit(f"Missing {labels}. Run train_classifier.py first.")

    shutil.copy2(model, target / "model.tflite")
    shutil.copy2(labels, target / "labels.json")
    if metrics.exists():
        shutil.copy2(metrics, target / "metrics.json")

    import json
    class_count = len(json.loads(labels.read_text(encoding="utf-8")))
    guidance = {
        "notice": "Draft IP102 pest guidance. Expert confirmation is required before pesticide use.",
        "default_next_step": "Capture a clear close-up image, monitor spread, and seek supporter verification for chemical action.",
    }
    write_json(target / "guidance.json", guidance)
    write_json(
        target / "manifest.json",
        {
            "model_id": "ip102-pest-v1",
            "model_version": "offline-tflite-v1",
            "dataset": "IP102",
            "task": "classification",
            "model_asset": f"assets/inference/models/{args.bundle_name}/model.tflite",
            "labels_asset": f"assets/inference/models/{args.bundle_name}/labels.json",
            "guidance_asset": f"assets/inference/models/{args.bundle_name}/guidance.json",
            "class_count": class_count,
            "input_width": args.image_size,
            "input_height": args.image_size,
            "confidence_threshold": args.confidence_threshold,
            "margin_threshold": args.margin_threshold,
        },
    )
    print(f"Packaged Flutter IP102 bundle at {target}")


if __name__ == "__main__":
    main()
