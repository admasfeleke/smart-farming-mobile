from __future__ import annotations

import argparse
from pathlib import Path

import tensorflow as tf


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export SavedModel to TFLite.")
    parser.add_argument("--saved-model", required=True, type=Path)
    parser.add_argument("--output-model", required=True, type=Path)
    parser.add_argument("--float16", action="store_true", default=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    converter = tf.lite.TFLiteConverter.from_saved_model(str(args.saved_model))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    if args.float16:
        converter.target_spec.supported_types = [tf.float16]
    tflite_model = converter.convert()
    args.output_model.parent.mkdir(parents=True, exist_ok=True)
    args.output_model.write_bytes(tflite_model)
    print(f"Wrote {args.output_model} ({len(tflite_model)} bytes)")


if __name__ == "__main__":
    main()
