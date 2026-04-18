"""Flag questions where the `correctChoice` label text does not appear
anywhere in the explanation.

This is a lightweight proxy for "answer-choice labels got swapped with a
different section of the book during PDF extraction" — see
``tool/fix_gi_liver_choice_leaks.py`` for an example of the real-world
failure mode this catches.

Heuristic
---------
For every question in ``assets/data/questions.json`` we:

  1. Take the label string under ``choices[correctChoice]``.
  2. Produce a set of content tokens from that label (alphanumeric words
     of length >= 4, lowercased; "cell", "tumor", "disease" etc. are too
     generic to count as evidence and are ignored).
  3. Require at least one of those tokens to appear in the explanation
     text (case-insensitive). If none do, we flag the question as a
     candidate.

To reduce false positives on genuinely acronymed/short-label answers
such as "MRI" or "Yes", labels that produce no content tokens at all
are skipped (cannot be audited this way).

Write a JSON report to ``assets/data/choice_label_audit.json`` and
print a concise summary grouped by book/chapter. Does NOT modify
questions.

Run: `python tool/audit_choice_explanation_mismatch.py`
"""

from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
QUESTIONS_PATH = REPO / "assets" / "data" / "questions.json"
REPORT_PATH = REPO / "assets" / "data" / "choice_label_audit.json"

# Tokens that are too generic to serve as evidence on their own.
_STOPWORDS = frozenset(
    {
        "above",
        "acute",
        "answer",
        "appearance",
        "associated",
        "benign",
        "bilateral",
        "blood",
        "body",
        "carcinoma",
        "cavity",
        "cell",
        "change",
        "changes",
        "choice",
        "chronic",
        "clinical",
        "condition",
        "correct",
        "diagnosis",
        "disease",
        "disorder",
        "effect",
        "enhancement",
        "evaluation",
        "evidence",
        "feature",
        "features",
        "finding",
        "findings",
        "fluid",
        "focal",
        "following",
        "history",
        "image",
        "images",
        "increase",
        "increased",
        "intravenous",
        "large",
        "lesion",
        "lesions",
        "level",
        "likely",
        "mass",
        "masses",
        "most",
        "none",
        "noncontrast",
        "normal",
        "patient",
        "patients",
        "pattern",
        "phase",
        "possible",
        "previous",
        "primary",
        "process",
        "protein",
        "question",
        "related",
        "right",
        "left",
        "scan",
        "setting",
        "shown",
        "signal",
        "small",
        "soft",
        "study",
        "structure",
        "syndrome",
        "system",
        "tissue",
        "tumor",
        "tumors",
        "type",
        "types",
        "typical",
        "view",
        "vessel",
        "vessels",
        "wide",
        "without",
    }
)

_WORD_RE = re.compile(r"[A-Za-z][A-Za-z0-9\-']+")


def _tokens(text: str) -> set[str]:
    out: set[str] = set()
    for m in _WORD_RE.finditer(text):
        w = m.group(0).lower()
        if len(w) < 4:
            continue
        if w in _STOPWORDS:
            continue
        out.add(w)
    return out


def _audit(data: list[dict]) -> list[dict]:
    flagged: list[dict] = []
    for q in data:
        letter = q.get("correctChoice")
        choices = q.get("choices") or {}
        if not letter or letter not in choices:
            continue
        label = str(choices[letter] or "").strip()
        if not label:
            continue
        label_tokens = _tokens(label)
        if not label_tokens:
            # Not auditable (e.g. "Yes", "A", numeric).
            continue

        explanation = str(q.get("explanation") or "")
        prompt = str(q.get("prompt") or "")
        haystack = (explanation + "\n" + prompt).lower()
        if any(tok in haystack for tok in label_tokens):
            continue

        flagged.append(
            {
                "id": q["id"],
                "bookId": q.get("bookId"),
                "chapterId": q.get("chapterId"),
                "chapterNumber": q.get("chapterNumber"),
                "questionNumber": q.get("questionNumber"),
                "correctChoice": letter,
                "correctLabel": label,
                "labelTokens": sorted(label_tokens),
                "promptHead": prompt[:140],
                "explanationHead": explanation[:200],
                "allChoiceLabels": {k: choices[k] for k in choices},
            }
        )
    return flagged


def main() -> None:
    data = json.loads(QUESTIONS_PATH.read_text(encoding="utf-8"))
    flagged = _audit(data)

    by_bookchap: dict[tuple[str, int], int] = defaultdict(int)
    for f in flagged:
        by_bookchap[(f["bookId"] or "?", f["chapterNumber"] or 0)] += 1

    REPORT_PATH.write_text(
        json.dumps(
            {"total": len(flagged), "issues": flagged},
            indent=2,
            ensure_ascii=True,
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"Audited {len(data)} questions. Flagged {len(flagged)}.")
    print("\nTop book/chapter concentrations (>=3):")
    rows = sorted(by_bookchap.items(), key=lambda kv: (-kv[1], kv[0]))
    for (book, chap), count in rows:
        if count < 3:
            continue
        print(f"  {book} ch{chap:>2}: {count}")
    print(f"\nFull report: {REPORT_PATH.relative_to(REPO)}")


if __name__ == "__main__":
    main()
