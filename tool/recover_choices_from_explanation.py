#!/usr/bin/env python3
"""
Fill empty or sparse MCQ choices by parsing explanation blocks like:

  In answer B, ...
  Answer A demonstrates ...

Conservative: requires at lab2 distinct lettered blocks; skips ambiguous rows.
Run before apply_content_validation_fixes.py for remaining gaps.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

_ANSWER_HEAD = re.compile(
    r"(?is)(?:^|\n)\s*(?:In answer|Answer)\s+([A-H])\b[,.\s:-]*\s*",
)
_VALID = frozenset("ABCDEFGH")
_WHITESPACE = re.compile(r"\s+")


def _extract_from_explanation(explanation: str) -> dict[str, str]:
    text = explanation.strip()
    if not text:
        return {}
    matches = list(_ANSWER_HEAD.finditer(text))
    if len(matches) < 2:
        return {}
    out: dict[str, str] = {}
    for i, m in enumerate(matches):
        letter = m.group(1).upper()
        if letter not in _VALID:
            continue
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[start:end].strip()
        body = _WHITESPACE.sub(" ", body)
        if body:
            out[letter] = body
    return out


def _fix_question(q: dict) -> bool:
    ch = q.get("choices")
    if not isinstance(ch, dict):
        ch = {}
    if len(ch) >= 2:
        return False
    expl = str(q.get("explanation", "") or "")
    recovered = _extract_from_explanation(expl)
    if len(recovered) < 2:
        return False
    merged = dict(ch)
    merged.update(recovered)
    if len(merged) < 2:
        return False
    q["choices"] = merged
    q.pop("validationRelaxed", None)
    return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print IDs that would change without writing.",
    )
    args = parser.parse_args()
    root = args.project_root.expanduser().resolve()
    path = root / "assets" / "data" / "questions.json"
    rows: list[dict] = json.loads(path.read_text(encoding="utf-8"))
    changed: list[str] = []
    for q in rows:
        if _fix_question(q):
            changed.append(str(q["id"]))
    if args.dry_run:
        print(f"Would update {len(changed)} questions:")
        for qid in changed:
            print(f"  {qid}")
        return
    path.write_text(json.dumps(rows, indent=2), encoding="utf-8")
    print(f"Updated {len(changed)} questions (recovered choices from explanation)")
    for qid in changed[:30]:
        print(f"  {qid}")
    if len(changed) > 30:
        print(f"  ... and {len(changed) - 30} more")


if __name__ == "__main__":
    main()
