#!/usr/bin/env python3
"""Audit explanation text for PDF-extraction formatting artifacts.

Reports three independent issue classes:

  1. soft line breaks   - single `\\n` mid-sentence that should be a space
  2. page artifacts     - lines that look like stray page numbers / footers
  3. truncation starters - explanation begins with a broken word (e.g. "hoice")

Usage:
    python tool/audit_explanation_format.py
    python tool/audit_explanation_format.py --max-samples 5
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

# Section headers from lib/utils/explanation_format.dart + matching-question
# line starts from questions that enumerate per-patient answers.
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

# Looks like a standalone "page number" artifact: a whole line that is only a
# small integer, or `p. 123` / `pg 123` with no other words.
_PAGE_ARTIFACT = re.compile(r"^\s*(?:(?:p\.?|pg\.?|page)\s*)?\d{1,4}\s*$", re.IGNORECASE)

# Common extraction truncations at the start of an explanation.
_TRUNCATION_STARTS = (
    "hoice",
    "hoices",
    "ecause",
    "emonstrates",
    "orrect",
    "nswer",
    "mage",
    "ince",
    "his ",
    "hese ",
    "he ",
    "n the ",
    "n this ",
    "hen ",
    "or ",
    "nitial",
)

_SENTENCE_END = re.compile(r'[.?!:;]["\')\]]?\s*$')


def _is_soft_break(before: str, after: str) -> bool:
    """A `\\n` between `before` and `after` is a soft break (should be a space)
    when the previous chunk does not end a sentence and the next chunk is not a
    protected header/enumeration."""
    if _SENTENCE_END.search(before):
        return False
    if _PROTECTED_PREFIXES.match(after):
        return False
    return True


def _truncation_start(text: str) -> str | None:
    stripped = text.lstrip()
    for prefix in _TRUNCATION_STARTS:
        if stripped.startswith(prefix):
            first = stripped.split(None, 1)[0][: len(prefix) + 2]
            return first
    return None


def audit_explanation(text: str) -> dict[str, list[str]]:
    """Return findings per class for a single explanation string."""
    findings: dict[str, list[str]] = {
        "soft_break": [],
        "page_artifact": [],
        "truncation_start": [],
    }
    if not text:
        return findings

    lines = text.split("\n")
    for idx in range(len(lines) - 1):
        before = lines[idx]
        after = lines[idx + 1]
        if _is_soft_break(before, after):
            tail = before[-30:].lstrip()
            head = after[:30].rstrip()
            findings["soft_break"].append(f"...{tail}[NL]{head}...")

    for line in lines:
        if _PAGE_ARTIFACT.match(line) and line.strip():
            findings["page_artifact"].append(line.strip())

    trunc = _truncation_start(text)
    if trunc is not None:
        findings["truncation_start"].append(trunc)

    return findings


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument(
        "--max-samples",
        type=int,
        default=3,
        help="Sample snippets to print per book per category (default: 3).",
    )
    args = parser.parse_args()

    root = args.project_root.expanduser().resolve()
    path = root / "assets" / "data" / "questions.json"
    questions: list[dict] = json.loads(path.read_text(encoding="utf-8"))

    categories = ("soft_break", "page_artifact", "truncation_start")
    per_book: dict[str, dict[str, list[tuple[str, str]]]] = {}
    total_q_with_issue = 0
    per_category: dict[str, int] = {c: 0 for c in categories}

    for question in questions:
        text = str(question.get("explanation") or "")
        findings = audit_explanation(text)
        if not any(findings.values()):
            continue
        total_q_with_issue += 1
        book = str(question.get("bookId") or "unknown")
        qid = str(question.get("id") or "?")
        bucket = per_book.setdefault(book, {c: [] for c in categories})
        for category in categories:
            for sample in findings[category]:
                bucket[category].append((qid, sample))
                per_category[category] += 1

    print("=" * 72)
    print("EXPLANATION FORMAT AUDIT")
    print("=" * 72)
    print(f"Total questions:                  {len(questions)}")
    print(f"Questions with any issue:         {total_q_with_issue}")
    for category in categories:
        print(f"  {category:20s} occurrences:  {per_category[category]}")
    print()

    for book in sorted(per_book.keys()):
        bucket = per_book[book]
        affected = sum(len(items) for items in bucket.values())
        if affected == 0:
            continue
        print(f"--- {book} ({affected} occurrences) ---")
        for category in categories:
            items = bucket[category]
            if not items:
                continue
            print(f"  {category}: {len(items)}")
            seen_ids: set[str] = set()
            shown = 0
            for qid, sample in items:
                if shown >= args.max_samples:
                    break
                if qid in seen_ids:
                    continue
                seen_ids.add(qid)
                shown += 1
                print(f"    {qid}: {sample}")
            remaining = len(items) - shown
            if remaining > 0:
                print(f"    ... and {remaining} more")
        print()


if __name__ == "__main__":
    main()
