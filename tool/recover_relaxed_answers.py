#!/usr/bin/env python3
"""
Try to recover correctChoice for validationRelaxed rows using explanation text only.

Conservative rules (skip if ambiguous):
- 'Answer:' / 'Answer is' (singular Answer, not 'Answers:') + single letter
- 'The correct answer is X' / 'correct choice is X'
- First sentence before '.' exactly matches a choice string (Oligoclonal bands. -> B)
- 'N[a-z] Answers: 1. A 2. B ...' with id suffix letter -> pick k-th pair (a=1, b=2, ...)
  Skips structure-mapping keys like '26b Answers: A. 7. Pyriform'
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

_VALID = frozenset("ABCDEFGH")

# Singular "Answer" with colon or "is" — avoids matching "Answers:" blocks.
_ANSWER_COLON_RE = re.compile(
    r"(?<![A-Za-z])Answer\s*:\s*([A-H])\b",
    re.IGNORECASE,
)
_ANSWER_IS_RE = re.compile(
    r"(?<![A-Za-z])Answer\s+is\s+([A-H])\b",
    re.IGNORECASE,
)
# "Answer B." OCR style (no colon)
_ANSWER_LETTER_DOT_RE = re.compile(
    r"(?<![A-Za-z])Answers?\s+([A-H])\s*\.",
    re.IGNORECASE,
)
# "Answer C Choice C ..." pattern (e.g. "Answer C Choice C, Assessment for ...")
_ANSWER_LETTER_CHOICE_RE = re.compile(
    r"(?<![A-Za-z])Answers?\s+([A-H])\s+Choice\s+[A-H]",
    re.IGNORECASE,
)
# "Answer C ..." (do not add a lookahead past the letter — "Answer C Choice" is valid OCR)
_ANSWER_LETTER_PLAIN_RE = re.compile(
    r"(?<![A-Za-z])Answers?\s+([A-H])\b",
    re.IGNORECASE,
)
_CORRECT_IS_RE = re.compile(
    r"The\s+correct\s+(?:answer|choice)\s+is\s+([A-H])\b",
    re.IGNORECASE,
)
# "Answers\nA. Superior mesenteric..." block pattern (label-only lines after "Answers")
_ANSWERS_BLOCK_RE = re.compile(
    r"^Answers\s*\n([A-H])\.\s",
    re.IGNORECASE | re.MULTILINE,
)


def _parse_tail_id(qid: str) -> tuple[str | None, str | None]:
    """Return (digits, suffix_letter) from last segment e.g. '10b' -> ('10', 'b')."""
    tail = qid.rsplit("-", 1)[-1]
    m = re.match(r"^(\d+)([a-z])?$", tail, re.IGNORECASE)
    if not m:
        return None, None
    return m.group(1), (m.group(2) or "").lower() or None


def _numbered_pairs(line: str) -> list[tuple[int, str]]:
    return [(int(a), b.upper()) for a, b in re.findall(r"(\d+)\s*\.\s*([A-H])\b", line)]


def _is_structure_mapping_block(rest: str) -> bool:
    """A. 7. Label style mapping, not 1. D 2. B style."""
    return bool(re.search(r"\b[A-H]\s*\.\s*\d+\s*\.", rest))


def _recover_from_numbered_block(qid: str, explanation: str) -> str | None:
    """Match '12b Answers: 1. D 2. B' and map suffix b -> second answer."""
    digits, suff = _parse_tail_id(qid)
    if not digits or not suff:
        return None
    # Lines like 10b Answers: or 26b Answers:
    pat = re.compile(
        rf"{re.escape(digits)}{re.escape(suff)}\s+Answers?\s*:\s*(.+?)(?:\n\n|$)",
        re.IGNORECASE | re.DOTALL,
    )
    m = pat.search(explanation)
    if not m:
        return None
    rest = m.group(1).strip()
    if _is_structure_mapping_block(rest):
        return None
    pairs = _numbered_pairs(rest)
    if not pairs:
        return None
    idx = ord(suff) - ord("a") + 1
    by_num = {n: letter for n, letter in pairs}
    if idx in by_num:
        return by_num[idx]
    if idx <= len(pairs):
        return pairs[idx - 1][1]
    return None


def _recover_answer_line(explanation: str) -> str | None:
    for rx in (
        _ANSWER_COLON_RE,
        _ANSWER_IS_RE,
        _ANSWER_LETTER_CHOICE_RE,
        _ANSWER_LETTER_DOT_RE,
        _ANSWER_LETTER_PLAIN_RE,
        _CORRECT_IS_RE,
    ):
        m = rx.search(explanation)
        if m:
            return m.group(1).upper()
    return None


def _recover_first_sentence_match(choices: dict[str, str], explanation: str) -> str | None:
    if not choices:
        return None
    first = explanation.strip().split(".", 1)[0].strip()
    if len(first) < 3:
        return None
    fl = first.lower()
    for letter, text in choices.items():
        if len(letter) != 1 or letter not in _VALID:
            continue
        tl = text.strip().lower()
        if not tl:
            continue
        if fl == tl or fl.startswith(tl[: min(25, len(tl))]):
            return letter
    return None


def _recover_explanation_choice_match(choices: dict[str, str], explanation: str) -> str | None:
    """Try to match the beginning of the explanation to one of the choice values."""
    if not choices or not explanation:
        return None
    expl_stripped = explanation.strip()
    expl_words = expl_stripped.split()
    if len(expl_words) < 2:
        return None
    expl_lower = expl_stripped.lower()
    expl_first = re.split(r"[,.:;!?]", expl_lower, maxsplit=1)[0].strip()
    best_letter: str | None = None
    best_length = 0
    for letter, text in choices.items():
        if len(letter) != 1 or letter not in _VALID:
            continue
        tl = text.strip().lower()
        if not tl or len(tl) < 3:
            continue
        if tl.startswith("[option"):
            continue
        if expl_lower.startswith(tl[:40]) and len(tl) > best_length:
            best_letter = letter
            best_length = len(tl)
        elif len(expl_first) >= 5 and expl_first in tl and len(expl_first) > best_length:
            best_letter = letter
            best_length = len(expl_first)
        elif len(tl) > 10:
            tl_words = tl.split()
            if len(tl_words) >= 2:
                suffix = " ".join(tl_words[-min(3, len(tl_words)):])
                if expl_lower.startswith(suffix) and len(suffix) > best_length:
                    best_letter = letter
                    best_length = len(suffix)
    return best_letter


def recover_letter(qid: str, row: dict) -> str | None:
    expl = str(row.get("explanation", "") or "")
    choices = row.get("choices") or {}
    if not isinstance(choices, dict):
        choices = {}

    letter = _recover_answer_line(expl)
    if letter and letter in choices:
        return letter

    letter = _recover_from_numbered_block(qid, expl)
    if letter and letter in choices:
        return letter

    letter = _recover_first_sentence_match(choices, expl)
    if letter:
        return letter

    letter = _recover_explanation_choice_match(choices, expl)
    if letter:
        return letter

    return None


def _ensure_choice_keys(row: dict, letter: str) -> None:
    ch = row.get("choices")
    if not isinstance(ch, dict):
        ch = {}
    if letter not in ch:
        ch[letter] = f"[Option {letter}] See figures and stem in the source chapter."
    if len(ch) < 2:
        for L in "ABCD":
            if L not in ch:
                ch[L] = (
                    f"[Option {L}] See the figures and stem in the source chapter."
                )
    row["choices"] = ch


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
        help="Print actions without writing questions.json",
    )
    args = parser.parse_args()
    root = args.project_root.expanduser().resolve()
    path = root / "assets" / "data" / "questions.json"
    rows: list[dict] = json.loads(path.read_text(encoding="utf-8"))

    recovered: list[str] = []
    skipped: list[str] = []

    for row in rows:
        if row.get("validationRelaxed") is not True:
            continue
        if row.get("questionType") == "matching" and row.get("matchingItems"):
            # Matching questions have no single correctChoice; skip recovery.
            continue
        qid = str(row["id"])
        letter = recover_letter(qid, row)
        if not letter:
            skipped.append(qid)
            continue
        _ensure_choice_keys(row, letter)
        row["correctChoice"] = letter
        row.pop("validationRelaxed", None)
        recovered.append(qid)

    print(f"Recovered {len(recovered)} question(s)")
    for qid in recovered:
        print(f"  ok {qid}")
    print(f"Still relaxed: {len(skipped)}")

    if args.dry_run:
        return

    path.write_text(json.dumps(rows, indent=2), encoding="utf-8")
    print(f"Wrote {path}")


if __name__ == "__main__":
    main()
