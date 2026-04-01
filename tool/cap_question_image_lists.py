#!/usr/bin/env python3
"""Cap imageAssets / explanationImageAssets per question (dedupe, preserve order).

After --apply, run:
  python tool/run_content_pipeline.py
"""

from __future__ import annotations

import argparse
import json
from copy import deepcopy
from pathlib import Path


def _unique_preserve(paths: object) -> list[str]:
    if not isinstance(paths, list):
        return []
    seen: set[str] = set()
    out: list[str] = []
    for p in paths:
        if not isinstance(p, str):
            continue
        t = p.strip()
        if not t or t in seen:
            continue
        seen.add(t)
        out.append(p)
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument(
        "--max-per-field",
        type=int,
        default=6,
        help="Max paths per imageAssets and per explanationImageAssets after dedupe.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write questions.json (default: dry-run only).",
    )
    args = parser.parse_args()
    path = args.project_root / "assets" / "data" / "questions.json"
    rows: list[dict] = json.loads(path.read_text(encoding="utf-8"))
    work = deepcopy(rows) if args.apply else rows

    touched = 0
    for row in work:
        snap = json.dumps(
            [row.get("imageAssets"), row.get("explanationImageAssets")],
            sort_keys=False,
        )
        for key in ("imageAssets", "explanationImageAssets"):
            u = _unique_preserve(row.get(key))
            row[key] = u[: args.max_per_field]
        after = json.dumps(
            [row.get("imageAssets"), row.get("explanationImageAssets")],
            sort_keys=False,
        )
        if snap != after:
            touched += 1

    print(
        f"Questions with lists deduped/capped: {touched} / {len(work)} "
        f"(max {args.max_per_field} per field)"
    )
    if args.apply:
        path.write_text(json.dumps(work, indent=2), encoding="utf-8")
        print(f"Wrote {path}")
    else:
        print("Dry-run only. Pass --apply to write.")


if __name__ == "__main__":
    main()
