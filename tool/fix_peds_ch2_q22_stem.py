"""Merge Pediatric Imaging Ch.2 Q22 into the Q20 neuroblastoma case.

Q22's prompt ("for evaluation of this tumor") is a follow-up to the
Q20/Q21 MIBG case but the extractor left it as an orphan stem group
with no images. Grouping it under stemGroup="20" lets the per-part
image fallback inherit Q20's CT/MR figures, and joining the existing
exam chain keeps it adjacent in custom exams.
"""
from __future__ import annotations

import json
from pathlib import Path

QUESTIONS_PATH = Path("assets/data/questions.json")
TARGET_ID = "pediatric-imaging-2-22"
EXPECTED_PROMPT_FRAGMENT = (
    "When performing an I-123 MIBG nuclear medicine examination for "
    "evaluation of this tumor"
)
NEW_STEM_GROUP = "20"
NEW_EXAM_CHAIN = "pediatric-imaging-chapter-2-seq-20"


def main() -> int:
    data = json.loads(QUESTIONS_PATH.read_text(encoding="utf-8"))
    target = None
    for q in data:
        if q.get("id") == TARGET_ID:
            target = q
            break
    if target is None:
        print(f"ERROR: {TARGET_ID} not found")
        return 1

    if EXPECTED_PROMPT_FRAGMENT not in target.get("prompt", ""):
        print(f"ERROR: unexpected prompt for {TARGET_ID}; aborting")
        return 1

    changed = False
    if target.get("stemGroup") != NEW_STEM_GROUP:
        target["stemGroup"] = NEW_STEM_GROUP
        changed = True
    if target.get("examChain") != NEW_EXAM_CHAIN:
        target["examChain"] = NEW_EXAM_CHAIN
        changed = True

    if not changed:
        print(f"No change needed for {TARGET_ID}")
        return 0

    QUESTIONS_PATH.write_text(
        json.dumps(data, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    print(f"Updated {TARGET_ID}: stemGroup={NEW_STEM_GROUP}, examChain={NEW_EXAM_CHAIN}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
