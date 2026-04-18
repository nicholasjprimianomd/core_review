"""Mark cardiac-1-19 as unrecoverable (choices + figure lost in extract).

`cardiac-1-19`'s prompt ("Which of the below shows the ideal contrast
bolus geometry?") requires a figure of four bolus-geometry graphs plus
four labeled answer choices; both were dropped during PDF extraction
(the stored `choices` are four empty strings). Apply the standard
`apply_content_validation_fixes.py` placeholder convention so the UI
does not render blank radio buttons and the validator stops flagging
the question.
"""
from __future__ import annotations

import json
from pathlib import Path

PATH = Path("assets/data/questions.json")
TARGET_ID = "cardiac-1-19"
LETTERS = "ABCD"


def main() -> int:
    data = json.loads(PATH.read_text(encoding="utf-8"))
    target = next((q for q in data if q.get("id") == TARGET_ID), None)
    if target is None:
        print(f"ERROR: {TARGET_ID} not found")
        return 1

    current_choices = target.get("choices") or {}
    if any(str(v).strip() for v in current_choices.values()):
        print(f"SKIP: {TARGET_ID} already has non-empty choice text")
        return 0

    target["choices"] = {
        letter: (
            f"[Option {letter}] See the figures and stem in the source chapter."
        )
        for letter in LETTERS
    }
    target["validationRelaxed"] = True
    target["correctChoice"] = ""

    PATH.write_text(
        json.dumps(data, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    print(f"Updated {TARGET_ID}: placeholder choices, validationRelaxed=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
