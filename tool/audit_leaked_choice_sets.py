#!/usr/bin/env python3
"""Find questions whose `choices` map is byte-identical to another
question's in the same book.

PDF extraction sometimes fails to parse a question's answer block
(typically when the choices live inside a figure/table, e.g. matching
questions) and falls back to the prior question's choices verbatim.
That leaves the wrong answer list attached to prompts whose content
talks about something entirely different.

The audit groups questions by (bookId, frozenset of choices items);
any group with more than one member is suspicious. We also flag
"matching-like" prompts (contain "match" + "(lettered)" or "(numbered)")
and explanations whose first characters look like a truncated
"A = N, B = N" mapping ("= 2, B = 3..."), because those two signals
almost always co-occur with this bug.

Writes: assets/data/leaked_choice_audit.json
"""
from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

QUESTIONS_PATH = Path("assets/data/questions.json")
REPORT_PATH = Path("assets/data/leaked_choice_audit.json")

MATCHING_PROMPT_RE = re.compile(r"\bmatch\b", re.IGNORECASE)
NUMBERED_PROMPT_RE = re.compile(r"\(numbered\)|\(lettered\)", re.IGNORECASE)
TRUNCATED_ANSWER_RE = re.compile(
    r"^\s*=\s*[A-Z0-9]+\s*[,;.]?\s*[A-Z]\s*=\s*[A-Z0-9]+",
    re.IGNORECASE,
)
FULL_ANSWER_MAP_RE = re.compile(
    r"^\s*[A-Z]\s*=\s*[A-Z0-9]+\s*[,;.]?\s*[A-Z]\s*=\s*[A-Z0-9]+",
    re.IGNORECASE,
)


def looks_like_matching_prompt(q: dict) -> bool:
    prompt = q.get("prompt") or ""
    if not MATCHING_PROMPT_RE.search(prompt):
        return False
    return bool(NUMBERED_PROMPT_RE.search(prompt)) or "Match the" in prompt


def looks_like_mapping_explanation(q: dict) -> bool:
    exp = (q.get("explanation") or "").lstrip()
    return bool(TRUNCATED_ANSWER_RE.match(exp) or FULL_ANSWER_MAP_RE.match(exp))


def choice_signature(choices: dict) -> tuple[tuple[str, str], ...]:
    return tuple(sorted((str(k), str(v)) for k, v in (choices or {}).items()))


def is_placeholder_bank(choices: dict) -> bool:
    if not choices:
        return False
    for v in choices.values():
        if "See the figures and stem in the source chapter" not in str(v):
            return False
    return True


def main() -> int:
    data = json.loads(QUESTIONS_PATH.read_text(encoding="utf-8"))
    by_group: dict[tuple, list[dict]] = defaultdict(list)
    for q in data:
        choices = q.get("choices") or {}
        if is_placeholder_bank(choices):
            # Questions with the standard "See source chapter" placeholder
            # independently share the same template; that is by design, not
            # a leak.
            continue
        sig = choice_signature(choices)
        if not sig:
            continue
        by_group[(q.get("bookId"), sig)].append(q)

    findings = []
    for (book_id, sig), members in by_group.items():
        if len(members) <= 1:
            continue
        flagged = []
        for m in members:
            flagged.append(
                {
                    "id": m["id"],
                    "prompt": (m.get("prompt") or "")[:300],
                    "correctChoice": m.get("correctChoice"),
                    "questionType": m.get("questionType", "single"),
                    "looks_like_matching_prompt": looks_like_matching_prompt(m),
                    "looks_like_mapping_explanation": (
                        looks_like_mapping_explanation(m)
                    ),
                    "explanation_head": (m.get("explanation") or "")[:120],
                }
            )
        suspect_count = sum(
            1
            for f in flagged
            if (
                f["looks_like_matching_prompt"]
                or f["looks_like_mapping_explanation"]
            )
        )
        if suspect_count == 0:
            continue
        findings.append(
            {
                "bookId": book_id,
                "duplicateCount": len(members),
                "suspectCount": suspect_count,
                "choices": dict(sig),
                "members": flagged,
            }
        )

    findings.sort(key=lambda f: (f["bookId"], -f["suspectCount"]))
    REPORT_PATH.write_text(
        json.dumps({"groups": findings}, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    total_suspects = sum(f["suspectCount"] for f in findings)
    print(
        f"Found {len(findings)} duplicate-choice groups spanning "
        f"{total_suspects} likely-leaked questions. "
        f"Report: {REPORT_PATH}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
