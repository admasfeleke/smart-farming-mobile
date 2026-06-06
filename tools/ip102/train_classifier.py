from __future__ import annotations

import argparse
from pathlib import Path

import tensorflow as tf

from common import write_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train a mobile IP102 classifier.")
    parser.add_argument("--data-root", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--image-size", default=224, type=int)
    parser.add_argument("--batch-size", default=32, type=int)
    parser.add_argument("--epochs", default=20, type=int)
    parser.add_argument("--fine-tune-epochs", default=8, type=int)
    parser.add_argument("--learning-rate", default=1e-3, type=float)
    return parser.parse_args()


def build_dataset(root: Path, split: str, image_size: int, batch_size: int, shuffle: bool):
    split_root = root / split
    if not split_root.exists():
      return None
    return tf.keras.utils.image_dataset_from_directory(
        split_root,
        image_size=(image_size, image_size),
        batch_size=batch_size,
        shuffle=shuffle,
        label_mode="categorical",
    )


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    train_ds = build_dataset(args.data_root, "train", args.image_size, args.batch_size, True)
    val_ds = build_dataset(args.data_root, "val", args.image_size, args.batch_size, False)
    if train_ds is None:
        raise SystemExit("Missing train split. Run prepare_subset.py first.")
    if val_ds is None:
        val_ds = build_dataset(args.data_root, "test", args.image_size, args.batch_size, False)
    if val_ds is None:
        raise SystemExit("Missing val/test split. Run prepare_subset.py first.")

    class_names = train_ds.class_names
    class_count = len(class_names)
    autotune = tf.data.AUTOTUNE
    train_ds = train_ds.prefetch(autotune)
    val_ds = val_ds.prefetch(autotune)

    augmentation = tf.keras.Sequential(
        [
            tf.keras.layers.RandomFlip("horizontal"),
            tf.keras.layers.RandomRotation(0.08),
            tf.keras.layers.RandomZoom(0.08),
            tf.keras.layers.RandomContrast(0.08),
        ],
        name="augmentation",
    )

    inputs = tf.keras.Input(shape=(args.image_size, args.image_size, 3))
    x = augmentation(inputs)
    x = tf.keras.applications.mobilenet_v3.preprocess_input(x)
    backbone = tf.keras.applications.MobileNetV3Small(
        include_top=False,
        weights="imagenet",
        input_shape=(args.image_size, args.image_size, 3),
    )
    backbone.trainable = False
    x = backbone(x, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.25)(x)
    outputs = tf.keras.layers.Dense(class_count, activation="softmax")(x)
    model = tf.keras.Model(inputs, outputs)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(args.learning_rate),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    head_history = model.fit(train_ds, validation_data=val_ds, epochs=args.epochs)

    backbone.trainable = True
    for layer in backbone.layers[:-24]:
        layer.trainable = False
    model.compile(
        optimizer=tf.keras.optimizers.Adam(args.learning_rate / 10),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    fine_history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=args.fine_tune_epochs,
    )

    saved_model_dir = args.output_dir / "saved_model"
    model.export(saved_model_dir)
    write_json(args.output_dir / "labels.json", class_names)
    write_json(
        args.output_dir / "metrics.json",
        {
            "dataset": "IP102",
            "task": "classification",
            "architecture": "MobileNetV3Small",
            "image_size": args.image_size,
            "class_count": class_count,
            "classes": class_names,
            "head_history": head_history.history,
            "fine_tune_history": fine_history.history,
        },
    )
    print(f"Saved model and labels to {args.output_dir}")


if __name__ == "__main__":
    main()
