#!/usr/bin/env python3
"""Fix questions whose `choices` map leaked verbatim from a neighbor.

Per `tool/audit_leaked_choice_sets.py`, a handful of questions in
`assets/data/questions.json` have `choices` that were copy-pasted from
a preceding question during PDF extraction. The affected prompts are
either:

  * Matching-style questions whose real answer bank lives inside an
    embedded figure/table that the extractor could not OCR (e.g.
    genitourinary-8-25 Belmont Report, genitourinary-8-30 fallopian
    tube segments, genitourinary-5-23 susceptibility class matching).

  * Short case-series diagnosis prompts whose real answer bank was in
    a shared figure (gastrointestinal-8-13/16/17/27/28/29/30).

In every case, the stored `choices` belong to an unrelated question
and actively mislead the reader. The standard remediation here is
what `tool/apply_content_validation_fixes.py` already uses for
un-scrapable options: replace with the
"[Option X] See the figures and stem in the source chapter." template
and flag `validationRelaxed`. The matching-style items additionally get
their truncated leading "A" restored in the explanation text and their
meaningless leaked `correctChoice` cleared.

Run:  python tool/fix_leaked_choice_sets.py
"""
from __future__ import annotations

import json
from pathlib import Path

QUESTIONS_PATH = Path("assets/data/questions.json")

# Matching-style victims: the real "choices" bank lives in the book
# figure (lettered research practices / segments / materials). The
# answer key letters in the explanation are the *items being matched*,
# not the student-facing choices, so we clear correctChoice and record
# that validation is relaxed for these.
MATCHING_VICTIMS = [
    {
        "id": "genitourinary-8-25",
        "prompt_contains": "Belmont Report",
        "expected_leaked_A": "Further imaging: follow-up ultrasound in 2 months",
        "truncation_fix": {
            "old": "= 2, B = 3, C = 1.",
            "new": "A = 2, B = 3, C = 1.",
        },
        "placeholder_letters": "ABCDE",
    },
    {
        "id": "genitourinary-8-30",
        "prompt_contains": "fallopian tube",
        "expected_leaked_A": "Further imaging: follow-up ultrasound in 2 months",
        "truncation_fix": {
            "old": "= 3, B = 1, C = 4, D = 2.",
            "new": "A = 3, B = 1, C = 4, D = 2.",
        },
        "placeholder_letters": "ABCDE",
    },
    {
        "id": "genitourinary-5-23",
        "prompt_contains": "class of susceptibility",
        "expected_leaked_A": "T1",
        "truncation_fix": {
            "old": "-4, B-1, C-3, D-2.",
            "new": "A-4, B-1, C-3, D-2.",
        },
        "placeholder_letters": "ABCDE",
    },
]

# Diagnosis case-series victims in Gastrointestinal Chapter 8. Their
# correctChoice letters (from the book's real answer key) align with
# their explanations so we preserve them; only the leaked anatomic
# labeling `choices` are replaced with placeholders.
DIAGNOSIS_VICTIMS = [
    {
        "id": "gastrointestinal-8-13",
        "expected_leaked_A": "Common hepatic duct",
        "placeholder_letters": "ABCDEF",
    },
    {
        "id": "gastrointestinal-8-16",
        "expected_leaked_A": "Common hepatic duct",
        "placeholder_letters": "ABCDEF",
    },
    {
        "id": "gastrointestinal-8-17",
        "expected_leaked_A": "Common hepatic duct",
        "placeholder_letters": "ABCDEF",
    },
    {
        "id": "gastrointestinal-8-27",
        "expected_leaked_A": "Common hepatic duct",
        "placeholder_letters": "ABCDEF",
    },
    {
        "id": "gastrointestinal-8-28",
        "expected_leaked_A": "Common hepatic duct",
        "placeholder_letters": "ABCDEF",
    },
    {
        "id": "gastrointestinal-8-29",
        "expected_leaked_A": "Common hepatic duct",
        "placeholder_letters": "ABCDEF",
    },
    {
        "id": "gastrointestinal-8-30",
        "expected_leaked_A": "Common hepatic duct",
        "placeholder_letters": "ABCDEF",
    },
]


def placeholder_choices(letters: str) -> dict:
    return {
        letter: (
            f"[Option {letter}] See the figures and stem in the source chapter."
        )
        for letter in letters
    }


def apply_fix(q: dict, spec: dict, is_matching: bool) -> str | None:
    choices = q.get("choices") or {}
    if choices.get("A") != spec["expected_leaked_A"]:
        return f"SKIP {q['id']}: choice A does not match expected leak"
    if "prompt_contains" in spec and spec["prompt_contains"] not in (
        q.get("prompt") or ""
    ):
        return f"SKIP {q['id']}: prompt does not match expected"

    q["choices"] = placeholder_choices(spec["placeholder_letters"])
    q["validationRelaxed"] = True

    if is_matching:
        q["correctChoice"] = ""
        old = spec["truncation_fix"]["old"]
        new = spec["truncation_fix"]["new"]
        expl = q.get("explanation", "") or ""
        if expl.lstrip().startswith(old):
            leading = expl[: len(expl) - len(expl.lstrip())]
            q["explanation"] = leading + new + expl.lstrip()[len(old):]
    return None


def main() -> int:
    data = json.loads(QUESTIONS_PATH.read_text(encoding="utf-8"))
    index = {q["id"]: q for q in data}
    notes = []
    applied = 0
    skipped = 0

    for spec in MATCHING_VICTIMS:
        q = index.get(spec["id"])
        if q is None:
            notes.append(f"MISSING {spec['id']}")
            skipped += 1
            continue
        msg = apply_fix(q, spec, is_matching=True)
        if msg is None:
            applied += 1
        else:
            notes.append(msg)
            skipped += 1

    for spec in DIAGNOSIS_VICTIMS:
        q = index.get(spec["id"])
        if q is None:
            notes.append(f"MISSING {spec['id']}")
            skipped += 1
            continue
        msg = apply_fix(q, spec, is_matching=False)
        if msg is None:
            applied += 1
        else:
            notes.append(msg)
            skipped += 1

    QUESTIONS_PATH.write_text(
        json.dumps(data, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    print(f"Applied {applied} fixes, skipped {skipped}.")
    for n in notes:
        print(f"  - {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
