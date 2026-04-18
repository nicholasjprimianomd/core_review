#!/usr/bin/env python3
"""Normalize explanation text in assets/data/questions.json.

Fixes three classes of PDF-extraction artifacts:

  1. Trailing or standalone page footers  (e.g. `P.78` / a lone `\\n61\\n`)
  2. Page numbers wrapped into prose       (e.g. `compresses the\\n61 pyloric channel`)
  3. Soft line breaks mid-sentence          (`on the\\nCT image` -> `on the CT image`)
  4. Truncated leading letters              (`hoice A is...` -> `Choice A is...`)

Usage:
    python tool/normalize_explanation_text.py               # dry run
    python tool/normalize_explanation_text.py --apply       # rewrite file
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

# Do not merge a newline when the next line starts with one of these - they are
# real paragraph / list starts (section headers, matching enumerations, etc.).
_PROTECTED_PREFIXES = re.compile(
    r"^\s*("
    r"Imaging\s+Findings|"
    r"Discussion|"
    r"Differential\s+Diagnosis|"
    r"Differential\s+considerations|"
    r"Clinical\s+(?:presentation|features)|"
    r"Pathophysiology|"
    r"Key\s+points?|"
    r"Pearls?|"
    r"Matching\s+answers?|"
    r"Patient\s+\d+[:.)]|"
    r"Case\s+\d+[:.)]|"
    r"Answer\s+[A-H][:.)]|"
    r"Option\s+[A-H][:.)]"
    r")",
    re.IGNORECASE,
)

# Sentence-ending punctuation followed by optional closing quote/paren.
_SENTENCE_END = re.compile(r"[.?!:;][\"')\]]?\s*$")

# Tokens that, if they appear immediately before or after a `\n<digits>`
# segment, indicate the digits are part of a legitimate measurement/range -
# not a stray page artifact.
_NUMBER_CONTEXT_PREV = {
    "to", "and", "or", "through", "than", "over", "under", "above", "below",
    "about", "approximately", "exceed", "exceeds", "exceeded", "least", "most",
    "maximum", "minimum", "up", "down", "from", "between", "near", "around",
    "nearly", "roughly", "only", "by", "at", "of",
}
_NUMBER_CONTEXT_NEXT = {
    "to", "and", "or", "through", "thru", "times", "fold", "cases", "patients",
    "ml", "mg", "mcg", "g", "kg", "cm", "mm", "m", "hz", "mhz", "khz",
    "msec", "ms", "sec", "min", "hr", "hrs", "hour", "hours",
    "days", "day", "weeks", "week", "years", "year", "month", "months",
    "degree", "degrees", "mgy", "msv", "gy", "sv", "kev", "mev", "kvp",
    "ma", "mas", "cm2", "mm2", "mm3", "cm3", "bpm", "fr", "french",
    "u", "iu", "mmol", "umol", "nmol", "ng", "nm", "mmhg", "mhz",
    "beats", "fps", "hounsfield", "hu", "mol", "percent",
}

# Explanation starts with a lowercase fragment that plainly lost its first
# letter during extraction. Keys must be exact prefixes; value is replacement.
_TRUNCATION_FIX: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"^hoices\b"), "Choices"),
    (re.compile(r"^hoice\b"), "Choice"),
    (re.compile(r"^ecause\b"), "Because"),
]


def _strip_trailing_page_footer(text: str) -> str:
    """Remove a trailing `P.123`, bare `123`, or `\\n\\n123` at end of text."""
    while True:
        new = re.sub(r"\n\s*(?:P\.?\s*)?\d{1,4}\s*$", "", text)
        if new == text:
            return text
        text = new


def _drop_standalone_digit_lines(text: str) -> str:
    """Remove lines that contain only a page number or `P.\\d+` marker."""
    lines = text.split("\n")
    out: list[str] = []
    for line in lines:
        if re.match(r"^\s*(?:P\.?\s*)?\d{1,4}\s*$", line):
            continue
        out.append(line)
    return "\n".join(out)


_WRAPPED_PAGE_RE = re.compile(
    r"(?P<prev>\S+)\n(?P<digits>\d{1,4})(?P<sep>[ \t]+)(?P<next>\S+)"
)


def _looks_like_page_artifact(prev: str, digits: str, nxt: str) -> bool:
    """True if `\\n<digits> <nxt>` in context of `<prev>\\n<digits> <nxt>` is a
    stranded page-number artifact rather than a wrapped measurement."""
    if prev[-1:].isdigit():
        return False
    prev_word = re.sub(r"[^A-Za-z]+$", "", prev).split()[-1:] or [""]
    if prev_word[0].lower() in _NUMBER_CONTEXT_PREV:
        return False
    if nxt[:1].isdigit():
        return False
    nxt_word = re.match(r"[A-Za-z]+", nxt)
    if nxt_word is None:
        return False
    if nxt_word.group(0).lower() in _NUMBER_CONTEXT_NEXT:
        return False
    # Only treat 2-4 digit numbers in a plausible textbook page range as
    # suspicious; 1-digit numbers are almost always prose ("1 of 3 cases").
    if not (10 <= int(digits) <= 999):
        return False
    return True


def _remove_wrapped_page_numbers(text: str) -> str:
    def _sub(match: re.Match[str]) -> str:
        prev = match.group("prev")
        digits = match.group("digits")
        nxt = match.group("next")
        if _looks_like_page_artifact(prev, digits, nxt):
            return f"{prev}\n{nxt}"
        return match.group(0)

    return _WRAPPED_PAGE_RE.sub(_sub, text)


def _merge_soft_breaks(text: str) -> str:
    """Join `\\n` that interrupts a sentence into a single space."""
    out: list[str] = []
    parts = text.split("\n")
    for idx, part in enumerate(parts):
        if idx == 0:
            out.append(part)
            continue
        prev_chunk = out[-1]
        if _SENTENCE_END.search(prev_chunk) or _PROTECTED_PREFIXES.match(part):
            out.append("\n")
            out.append(part)
            continue
        if prev_chunk.endswith(" ") or part.startswith(" "):
            out.append(part)
        else:
            out.append(" ")
            out.append(part)
    return "".join(out)


def _collapse_spaces(text: str) -> str:
    text = re.sub(r"[ \t]{2,}", " ", text)
    text = re.sub(r" +\n", "\n", text)
    text = re.sub(r"\n[ \t]+", "\n", text)
    return text


def _fix_truncation_start(text: str) -> str:
    for pat, repl in _TRUNCATION_FIX:
        if pat.match(text):
            return pat.sub(repl, text, count=1)
    return text


def normalize(text: str) -> str:
    if not text:
        return text
    text = _strip_trailing_page_footer(text)
    text = _drop_standalone_digit_lines(text)
    text = _remove_wrapped_page_numbers(text)
    text = _merge_soft_breaks(text)
    text = _collapse_spaces(text)
    text = _fix_truncation_start(text)
    return text.strip()


def _summarize_diff(before: str, after: str) -> tuple[int, int, int]:
    """Return (newlines_removed, chars_removed, any_change)."""
    nl = before.count("\n") - after.count("\n")
    chars = len(before) - len(after)
    return nl, chars, 1 if before != after else 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write normalized content back to questions.json.",
    )
    parser.add_argument(
        "--show",
        type=int,
        default=0,
        help="Print up to N before/after snippet pairs for questions that changed.",
    )
    args = parser.parse_args()

    root = args.project_root.expanduser().resolve()
    path = root / "assets" / "data" / "questions.json"
    questions: list[dict] = json.loads(path.read_text(encoding="utf-8"))

    total_changed = 0
    total_nl_removed = 0
    total_chars_removed = 0
    per_book: dict[str, int] = {}
    shown = 0

    for question in questions:
        original = str(question.get("explanation") or "")
        updated = normalize(original)
        if updated == original:
            continue
        nl, chars, changed = _summarize_diff(original, updated)
        total_changed += changed
        total_nl_removed += nl
        total_chars_removed += chars
        book = str(question.get("bookId") or "unknown")
        per_book[book] = per_book.get(book, 0) + 1
        question["explanation"] = updated

        if shown < args.show:
            shown += 1
            print(f"--- {question.get('id')} ({book}) ---")
            before_head = original[:240].replace("\n", "\\n")
            after_head = updated[:240].replace("\n", "\\n")
            print(f"  before: {before_head}")
            print(f"  after : {after_head}")

    print()
    print("=" * 72)
    print("EXPLANATION NORMALIZATION")
    print("=" * 72)
    print(f"Total questions:        {len(questions)}")
    print(f"Questions changed:      {total_changed}")
    print(f"Newlines removed:       {total_nl_removed}")
    print(f"Characters removed:     {total_chars_removed}")
    print()
    print("Per book:")
    for book in sorted(per_book.keys()):
        print(f"  {book:45s} {per_book[book]}")

    if args.apply and total_changed > 0:
        path.write_text(json.dumps(questions, indent=2), encoding="utf-8")
        print()
        print(f"Wrote {total_changed} updated explanations to {path.relative_to(root)}")
    elif not args.apply:
        print()
        print("Dry run. Re-run with --apply to write changes.")


if __name__ == "__main__":
    main()
