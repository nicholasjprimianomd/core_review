#!/usr/bin/env python3
"""Report questions with unusually many linked images (per book)."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=6,
        help="Flag rows where stem + explanation image paths exceed this count.",
    )
    args = parser.parse_args()
    path = args.project_root / "assets" / "data" / "questions.json"
    rows: list[dict] = json.loads(path.read_text(encoding="utf-8"))
    by_book: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for q in rows:
        bid = str(q.get("bookId", ""))
        qid = str(q.get("id", ""))
        stem = q.get("imageAssets") or []
        exp = q.get("explanationImageAssets") or []
        n = 0
        if isinstance(stem, list):
            n += len([p for p in stem if isinstance(p, str) and p.strip()])
        if isinstance(exp, list):
            n += len([p for p in exp if isinstance(p, str) and p.strip()])
        if n > args.threshold:
            by_book[bid].append((qid, n))

    for bid in sorted(by_book.keys()):
        items = sorted(by_book[bid], key=lambda t: -t[1])
        print(f"{bid}: {len(items)} questions over {args.threshold} images (top 5 by count)")
        for qid, n in items[:5]:
            print(f"  {n}  {qid}")
        if len(items) > 5:
            print(f"  ... and {len(items) - 5} more")


if __name__ == "__main__":
    main()
