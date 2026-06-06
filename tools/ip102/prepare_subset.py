from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from common import normalize_label, read_ip102_classes, write_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare a crop-aligned IP102 subset.")
    parser.add_argument("--dataset-root", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument(
        "--classes-file",
        default=Path(__file__).with_name("ip102_classes.txt"),
        type=Path,
    )
    parser.add_argument(
        "--class-name-contains",
        action="append",
        default=[],
        help="Case-insensitive class-name filter. Can be repeated.",
    )
    return parser.parse_args()


def find_split_files(root: Path) -> dict[str, Path]:
    candidates = {
        "train": ["train.txt", "trainval.txt"],
        "val": ["val.txt", "valid.txt", "validation.txt"],
        "test": ["test.txt"],
    }
    found: dict[str, Path] = {}
    for split, names in candidates.items():
        for name in names:
            matches = list(root.rglob(name))
            if matches:
                found[split] = matches[0]
                break
    return found


def find_image(root: Path, relative: str) -> Path | None:
    direct = root / relative
    if direct.exists():
        return direct
    basename = Path(relative).name
    matches = list(root.rglob(basename))
    return matches[0] if matches else None


def iter_split_rows(path: Path):
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        raw = line.strip()
        if not raw:
            continue
        parts = raw.split()
        if len(parts) < 2:
            continue
        image_path = parts[0]
        try:
            class_index = int(parts[-1])
        except ValueError:
            continue
        yield image_path, class_index


def main() -> None:
    args = parse_args()
    filters = [item.strip().lower() for item in args.class_name_contains if item.strip()]
    classes = read_ip102_classes(args.classes_file)
    if not classes:
        raise SystemExit(f"No IP102 classes found in {args.classes_file}")

    selected = {
        index: name
        for index, name in classes
        if not filters or any(token in name.lower() for token in filters)
    }
    if not selected:
        raise SystemExit("No IP102 classes matched the requested filters.")

    split_files = find_split_files(args.dataset_root)
    if not split_files:
        raise SystemExit("Could not find IP102 train/val/test split files.")

    args.output_root.mkdir(parents=True, exist_ok=True)
    labels = [selected[index] for index in sorted(selected)]
    label_map = {index: normalize_label(name) for index, name in selected.items()}
    write_json(args.output_root / "labels.json", labels)

    copied = 0
    for split, split_file in split_files.items():
        for relative_image, class_index in iter_split_rows(split_file):
            if class_index not in selected:
                continue
            source = find_image(args.dataset_root, relative_image)
            if source is None:
                continue
            target_dir = args.output_root / split / label_map[class_index]
            target_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target_dir / source.name)
            copied += 1

    write_json(
        args.output_root / "subset_manifest.json",
        {
            "source": "IP102",
            "filters": filters,
            "class_count": len(labels),
            "classes": labels,
            "images_copied": copied,
        },
    )
    print(f"Prepared {copied} images across {len(labels)} classes at {args.output_root}")


if __name__ == "__main__":
    main()
