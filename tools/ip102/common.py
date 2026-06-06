from __future__ import annotations

import json
from pathlib import Path


def read_ip102_classes(path: Path) -> list[tuple[int, str]]:
    classes: list[tuple[int, str]] = []
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        raw = line.strip()
        if not raw:
            continue
        parts = raw.split(maxsplit=1)
        if len(parts) != 2:
            continue
        try:
            index = int(parts[0])
        except ValueError:
            continue
        classes.append((index, " ".join(parts[1].split())))
    return classes


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def normalize_label(name: str) -> str:
    return "_".join(name.strip().lower().replace("/", " ").split())
