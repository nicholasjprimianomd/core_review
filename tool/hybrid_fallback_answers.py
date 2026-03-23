#!/usr/bin/env python3
"""Restore correctChoice/explanation/references from a prior questions.json when current row is empty."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--current", type=Path, required=True)
    parser.add_argument("--fallback", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()
    out = args.output or args.current

    cur: list[dict] = json.loads(args.current.read_text(encoding="utf-8"))
    fb: list[dict] = json.loads(args.fallback.read_text(encoding="utf-8"))
    fb_by_id = {q["id"]: q for q in fb}

    restored = 0
    for q in cur:
        old = fb_by_id.get(q["id"])
        if old is None:
            continue
        if not str(q.get("correctChoice", "")).strip() and str(
            old.get("correctChoice", "")
        ).strip():
            q["correctChoice"] = old["correctChoice"]
            restored += 1
        if not str(q.get("explanation", "")).strip() and str(
            old.get("explanation", "")
        ).strip():
            q["explanation"] = old["explanation"]
        if not q.get("references") and old.get("references"):
            q["references"] = list(old["references"])
        if (
            isinstance(q.get("choices"), dict)
            and len(q.get("choices") or {}) < 2
            and isinstance(old.get("choices"), dict)
            and len(old.get("choices") or {}) >= 2
        ):
            q["choices"] = dict(old["choices"])

    out.write_text(json.dumps(cur, indent=2), encoding="utf-8")
    print(f"Restored correctChoice from fallback for {restored} questions")
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
