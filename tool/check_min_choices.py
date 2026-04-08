#!/usr/bin/env python3
"""Fail if any question in assets/data/questions.json has fewer than 2 choices."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    args = parser.parse_args()
    root = args.project_root.expanduser().resolve()
    path = root / "assets" / "data" / "questions.json"
    rows: list[dict] = json.loads(path.read_text(encoding="utf-8"))
    bad: list[str] = []
    for q in rows:
        ch = q.get("choices")
        n = len(ch) if isinstance(ch, dict) else 0
        if n < 2:
            bad.append(str(q.get("id", "?")))
    if bad:
        print("Questions with fewer than 2 choices:", file=sys.stderr)
        for qid in bad:
            print(f"  {qid}", file=sys.stderr)
        raise SystemExit(1)
    print(f"check_min_choices OK ({len(rows)} questions)")


if __name__ == "__main__":
    main()
