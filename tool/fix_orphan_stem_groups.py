"""Merge orphan follow-up questions into the preceding case's stem group.

Some clinical cases in the source books span multiple numbered questions
(e.g. Q21 sets up the case, Q22 asks "What is the most appropriate next
step for management?"). The PDF extractor gives each numbered question
its own ``stemGroup``, which means the follow-up question renders in the
UI without the clinical history or images from the setup question.

This script fixes that by rewriting the follow-up question's ``stemGroup``
to match the setup question's ``stemGroup`` (and keeping them both in the
same chapter/section). Because ``stemGroupImageAssetsMerged`` and the
exam-block key both derive from ``multipartStemKey``, a single write is
enough:

* the quiz UI will show the setup question's images on the follow-up,
* custom exams keep the two parts together in order.

Candidates to add here are questions whose prompt has no clinical context
of its own (e.g. ``"What is the most appropriate next step for
management?"``) and whose preceding question in the same chapter has a
full clinical stem and images describing the same diagnosis. The audit
helper in this file prints likely candidates.

Run from the repo root:

    python tool/fix_orphan_stem_groups.py            # apply fixes
    python tool/fix_orphan_stem_groups.py --dry-run  # preview only
    python tool/fix_orphan_stem_groups.py --audit    # print detector output
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

QUESTIONS_PATH = Path("assets/data/questions.json")

# Each entry maps a follow-up question id to the question id it should
# inherit its stem/images from. Both ids must live in the same book,
# chapter, and section (the multipart key includes all three).
# Keep this list sorted by book id then chapter for readability.
STEM_GROUP_MERGES: dict[str, str] = {
    # Pediatric Imaging, Ch. 3 (MSK) - avulsion fracture case
    # Q22 ("Which of the following is TRUE?") is a follow-up to Q21's
    # avulsion fracture case; all choices discuss avulsion muscle
    # attachments.
    "pediatric-imaging-3-22": "pediatric-imaging-3-21",

    # Pediatric Imaging, Ch. 5 (Neuro) - medulloblastoma case
    # Q10 ("What is the next best step?") is a follow-up to Q9 about a
    # 12-year-old with ataxia and a midline posterior fossa mass.
    "pediatric-imaging-5-10": "pediatric-imaging-5-9",

    # Pediatric Imaging, Ch. 5 (Neuro) - vein of Galen malformation case
    # Q22 ("What is the most appropriate next step for management?") is
    # a follow-up to Q21 about a 1-year-old with VGAM; the explanation
    # references the same lesion and venous drainage.
    "pediatric-imaging-5-22": "pediatric-imaging-5-21",

    # Neuroradiology, Ch. 19 (CNS Angiography) - Moyamoya disease case
    # Q9 ("Which of the following is true regarding Moyamoya?") is a
    # follow-up knowledge question to Q8 (9-year-old with TIAs, answer
    # Moyamoya disease, with the angiogram images).
    "neuroradiology-19-9": "neuroradiology-19-8",
}


_CONTEXTLESS_PROMPT_RE = re.compile(
    r"^\s*(?:"
    r"what\s+is\s+(?:the\s+)?(?:most\s+likely\s+)?"
    r"(?:next\s+(?:best\s+)?step|most\s+appropriate\s+next\s+step|"
    r"diagnosis|treatment|management)"
    r"|which\s+of\s+the\s+following\s+is\s+true\s*\??"
    r")\b",
    re.IGNORECASE,
)

_CLINICAL_STEM_RE = re.compile(
    r"^\s*(?:an?|the)\s+\d+[-\s](?:day|week|month|year)[-\s]?old\b",
    re.IGNORECASE,
)


def _is_contextless_prompt(prompt: str) -> bool:
    p = (prompt or "").strip()
    if not p or len(p) > 160 or _CLINICAL_STEM_RE.search(p):
        return False
    return bool(_CONTEXTLESS_PROMPT_RE.match(p))


def _audit(questions: list[dict]) -> list[dict]:
    """Return likely-orphan follow-up rows (for manual review)."""
    key = lambda q: (q.get("bookId", ""), q.get("chapterId", ""), q.get("sectionId") or "")
    by_chapter: dict[tuple[str, str, str], list[dict]] = {}
    for q in questions:
        by_chapter.setdefault(key(q), []).append(q)

    flagged: list[dict] = []
    for group in by_chapter.values():
        group.sort(key=lambda q: q.get("sortOrder", 0))
        for i, q in enumerate(group):
            if i == 0:
                continue
            if q.get("imageAssets"):
                continue
            if not _is_contextless_prompt(q.get("prompt", "")):
                continue
            prev = group[i - 1]
            if not _CLINICAL_STEM_RE.search(prev.get("prompt", "")):
                continue
            if q.get("stemGroup") == prev.get("stemGroup"):
                continue
            flagged.append(
                {
                    "id": q["id"],
                    "prev_id": prev["id"],
                    "questionNumber": q.get("questionNumber"),
                    "prev_questionNumber": prev.get("questionNumber"),
                    "chapterTitle": q.get("chapterTitle"),
                    "prompt": q.get("prompt"),
                    "prev_prompt": prev.get("prompt"),
                    "stemGroup": q.get("stemGroup"),
                    "prev_stemGroup": prev.get("stemGroup"),
                    "prev_image_count": len(prev.get("imageAssets") or []),
                    "already_fixed": q["id"] in STEM_GROUP_MERGES,
                }
            )
    return flagged


def _same_scope(a: dict, b: dict) -> bool:
    return (
        a.get("bookId") == b.get("bookId")
        and a.get("chapterId") == b.get("chapterId")
        and (a.get("sectionId") or "") == (b.get("sectionId") or "")
    )


def _apply_merges(questions: list[dict]) -> tuple[int, list[str]]:
    by_id = {q["id"]: q for q in questions}
    changes = 0
    errors: list[str] = []

    for qid, source_id in STEM_GROUP_MERGES.items():
        follow_up = by_id.get(qid)
        setup = by_id.get(source_id)
        if follow_up is None or setup is None:
            errors.append(f"missing id(s) for merge {qid} <- {source_id}")
            continue
        if not _same_scope(follow_up, setup):
            errors.append(
                f"{qid} and {source_id} are not in the same "
                "book/chapter/section; refusing to merge"
            )
            continue
        target_group = setup.get("stemGroup")
        if not target_group:
            errors.append(f"{source_id} has no stemGroup; refusing to merge")
            continue
        if follow_up.get("stemGroup") != target_group:
            follow_up["stemGroup"] = target_group
            changes += 1
    return changes, errors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would change without writing questions.json.",
    )
    parser.add_argument(
        "--audit",
        action="store_true",
        help="Print candidate orphan follow-up questions and exit.",
    )
    args = parser.parse_args()

    questions_path = (args.project_root / QUESTIONS_PATH).resolve()
    questions = json.loads(questions_path.read_text(encoding="utf-8"))

    if args.audit:
        rows = _audit(questions)
        print(f"Found {len(rows)} candidate orphan follow-up question(s):")
        for r in rows:
            marker = "[FIXED]" if r["already_fixed"] else "[ ]    "
            print(
                f"  {marker} {r['id']}  "
                f"(prev {r['prev_questionNumber']} -> this {r['questionNumber']}, "
                f"ch={r['chapterTitle']})"
            )
            print(f"            prev: {r['prev_prompt'][:110]}")
            print(f"            this: {r['prompt'][:110]}")
            print(
                f"            prev stemGroup='{r['prev_stemGroup']}' "
                f"(imgs={r['prev_image_count']}), this stemGroup='{r['stemGroup']}'"
            )
        return

    changes, errors = _apply_merges(questions)
    for err in errors:
        print(f"WARN: {err}")

    if args.dry_run:
        print(f"Would apply {changes} stemGroup merge(s) across {len(STEM_GROUP_MERGES)} configured mapping(s).")
        return

    if changes:
        original = questions_path.read_bytes()
        eol = b"\r\n" if b"\r\n" in original[:4096] else b"\n"
        trailing = original.endswith(b"\r\n") or original.endswith(b"\n")
        body = json.dumps(questions, indent=2, ensure_ascii=True)
        if eol != b"\n":
            body = body.replace("\n", eol.decode("ascii"))
        if trailing and not body.endswith(eol.decode("ascii")):
            body += eol.decode("ascii")
        questions_path.write_bytes(body.encode("utf-8"))
        print(f"Applied {changes} stemGroup merge(s); wrote {questions_path}")
    else:
        print("No changes needed.")


if __name__ == "__main__":
    main()
