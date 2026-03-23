#!/usr/bin/env python3
"""Write tool/golden_baseline.json from assets/data/questions.json for regression checks."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument(
        "--ids",
        nargs="+",
        metavar="QUESTION_ID",
        help="If set, only these question ids are recorded (default: built-in curated list).",
    )
    args = parser.parse_args()
    root = args.project_root.expanduser().resolve()
    questions_path = root / "assets" / "data" / "questions.json"
    out_path = root / "tool" / "golden_baseline.json"

    default_ids = [
        "breast-imaging-1-1",
        "breast-imaging-1-10",
        "breast-imaging-1-11",
        "cardiac-1-1",
        "cardiac-1-10",
        "cardiac-1-11",
        "gastrointestinal-1-1",
        "gastrointestinal-1-10",
        "gastrointestinal-1-11",
        "genitourinary-1-1",
        "genitourinary-1-10",
        "genitourinary-1-11",
        "musculoskeletal-imaging-1-1",
        "musculoskeletal-imaging-1-10",
        "musculoskeletal-imaging-1-11",
        "neuroradiology-1-10a",
        "neuroradiology-1-10b",
        "neuroradiology-1-11a",
        "nuclear-medicine-1-1",
        "nuclear-medicine-1-2",
        "nuclear-medicine-1-3",
        "pediatric-imaging-1-1",
        "pediatric-imaging-1-10",
        "pediatric-imaging-1-11",
        "thoracic-imaging-1-1",
        "thoracic-imaging-1-10",
        "thoracic-imaging-1-11",
        "ultrasound-1-1",
        "ultrasound-1-11",
        "ultrasound-1-12",
        "vascular-and-interventional-radiology-1-1",
        "vascular-and-interventional-radiology-1-10",
        "vascular-and-interventional-radiology-1-11",
    ]
    want = set(args.ids) if args.ids else set(default_ids)

    rows: list[dict] = json.loads(questions_path.read_text(encoding="utf-8"))
    by_id = {q["id"]: q for q in rows}

    questions: dict[str, dict] = {}
    missing = sorted(want - set(by_id.keys()))
    if missing:
        raise SystemExit(f"Unknown question id(s): {missing}")

    for qid in sorted(want):
        q = by_id[qid]
        ch = q.get("choices") or {}
        letters = sorted(ch.keys()) if isinstance(ch, dict) else []
        expl = str(q.get("explanation", "") or "")
        questions[qid] = {
            "correctChoice": str(q.get("correctChoice", "") or "").strip(),
            "choiceLetters": letters,
            "minExplanationLen": max(0, len(expl) // 2),
        }

    payload = {
        "version": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": questions_path.relative_to(root).as_posix(),
        "questions": questions,
    }
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"Wrote {len(questions)} entries to {out_path}")


if __name__ == "__main__":
    main()
