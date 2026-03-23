#!/usr/bin/env python3
"""Fail if assets/data/questions.json regresses against tool/golden_baseline.json."""

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
    baseline_path = root / "tool" / "golden_baseline.json"
    questions_path = root / "assets" / "data" / "questions.json"

    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    rows: list[dict] = json.loads(questions_path.read_text(encoding="utf-8"))
    by_id = {q["id"]: q for q in rows}

    failures: list[str] = []
    for qid, spec in baseline["questions"].items():
        q = by_id.get(qid)
        if q is None:
            failures.append(f"{qid}: missing row")
            continue
        want_letter = spec.get("correctChoice", "")
        got_letter = str(q.get("correctChoice", "") or "").strip()
        if got_letter != want_letter:
            failures.append(
                f"{qid}: correctChoice was {want_letter!r}, now {got_letter!r}"
            )
        ch = q.get("choices") or {}
        got_letters = sorted(ch.keys()) if isinstance(ch, dict) else []
        want_letters = spec.get("choiceLetters") or []
        if set(got_letters) != set(want_letters):
            failures.append(
                f"{qid}: choice keys changed (was {want_letters}, now {got_letters})"
            )
        expl = str(q.get("explanation", "") or "")
        min_len = int(spec.get("minExplanationLen", 0))
        if len(expl) < min_len:
            failures.append(
                f"{qid}: explanation length {len(expl)} < baseline min {min_len}"
            )

    if failures:
        print("Golden baseline regressions:", file=sys.stderr)
        for line in failures:
            print(f"  {line}", file=sys.stderr)
        raise SystemExit(1)
    print(f"Golden baseline OK ({len(baseline['questions'])} questions)")


if __name__ == "__main__":
    main()
