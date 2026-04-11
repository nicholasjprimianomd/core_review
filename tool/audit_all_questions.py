#!/usr/bin/env python3
"""Comprehensive audit of all questions in questions.json.

Reports:
  1. Missing correctChoice (has >=2 choices but no answer)
  2. Missing choices (has correctChoice but <2 choices)
  3. Missing explanation
  4. Prompt mentions image but no stem images attached
  5. Explanation mentions image/figure but no explanation images attached
  6. Answer letter not in choices (correctChoice not a valid key)
  7. Questions with suspiciously many images (>4)

Outputs a summary + per-book breakdown.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

IMAGE_REFERENCE_RE = re.compile(
    r"\[image\]"
    r"|shown\s+(?:above|below|here)\b"
    r"|shown\s+is\b"
    r"|images?.*shown\b"
    r"|based on\s+(?:the|these|following|diagnostic|ultrasound|mammogram|mr|mri|ct).*images?"
    r"|the following images?\b"
    r"|images?\s+available\b"
    r"|pictured here\b",
    re.IGNORECASE,
)
_LOOSE_IMAGE_RE = re.compile(
    r"\b(below|provided|arrows?|arrowheads?|same patient|shown above|shown below)\b",
    re.IGNORECASE,
)
_PAREN_ANNOTATION_RE = re.compile(
    r"\(\s*(?:arrowheads?|arrows?|asterisks?|stars?|circle|dashed|open|closed)\b",
    re.IGNORECASE,
)
_PHASE_IMAGES_RE = re.compile(r"\bphase\s+images?\b", re.IGNORECASE)
FIGURE_REF_RE = re.compile(r"FIGURE\s+\d+", re.IGNORECASE)
MATCHING_EXPLANATION_RE = re.compile(r"Matching answers:", re.IGNORECASE)


def prompt_mentions_image(prompt: str) -> bool:
    return bool(
        IMAGE_REFERENCE_RE.search(prompt)
        or _LOOSE_IMAGE_RE.search(prompt)
        or _PAREN_ANNOTATION_RE.search(prompt)
        or _PHASE_IMAGES_RE.search(prompt)
    )


def explanation_mentions_figure(expl: str) -> bool:
    return bool(FIGURE_REF_RE.search(expl))


def main() -> None:
    repo = Path(__file__).resolve().parents[1]
    path = repo / "assets" / "data" / "questions.json"
    qs: list[dict] = json.loads(path.read_text(encoding="utf-8"))

    issues: dict[str, list[dict]] = {
        "missing_correct_choice": [],
        "missing_choices": [],
        "missing_explanation": [],
        "answer_not_in_choices": [],
        "prompt_mentions_image_no_stem_img": [],
        "explanation_mentions_figure_no_expl_img": [],
        "too_many_stem_images": [],
        "too_many_expl_images": [],
    }

    for q in qs:
        qid = q["id"]
        book = q["bookId"]
        ch = q.get("chapterNumber", "?")
        qnum = q.get("questionNumber", "?")
        label = f"{book} Ch{ch} Q{qnum}"

        cc = (q.get("correctChoice") or "").strip()
        choices = q.get("choices") or {}
        expl = (q.get("explanation") or "").strip()
        prompt = (q.get("prompt") or "").strip()
        stem_imgs = q.get("imageAssets") or []
        expl_imgs = q.get("explanationImageAssets") or []
        is_matching = bool(MATCHING_EXPLANATION_RE.search(expl))

        if not cc and len(choices) >= 2 and not is_matching:
            issues["missing_correct_choice"].append({"id": qid, "label": label, "choices": list(choices.keys())})

        if cc and len(choices) < 2 and not is_matching:
            issues["missing_choices"].append({"id": qid, "label": label, "cc": cc, "num_choices": len(choices)})

        if not expl and not is_matching:
            issues["missing_explanation"].append({"id": qid, "label": label})

        if cc and choices and cc not in choices and not is_matching:
            issues["answer_not_in_choices"].append({"id": qid, "label": label, "cc": cc, "choices": list(choices.keys())})

        if prompt_mentions_image(prompt) and not stem_imgs and not is_matching:
            issues["prompt_mentions_image_no_stem_img"].append({"id": qid, "label": label, "prompt_snippet": prompt[:100]})

        if explanation_mentions_figure(expl) and not expl_imgs and not stem_imgs:
            issues["explanation_mentions_figure_no_expl_img"].append({"id": qid, "label": label})

        if len(stem_imgs) > 4:
            issues["too_many_stem_images"].append({"id": qid, "label": label, "count": len(stem_imgs)})

        if len(expl_imgs) > 4:
            issues["too_many_expl_images"].append({"id": qid, "label": label, "count": len(expl_imgs)})

    print("=" * 70)
    print("QUESTION AUDIT REPORT")
    print("=" * 70)
    print(f"Total questions: {len(qs)}")
    print()

    total_issues = 0
    for category, items in issues.items():
        count = len(items)
        total_issues += count
        header = category.replace("_", " ").upper()
        print(f"--- {header}: {count} ---")
        if count > 0:
            by_book: dict[str, list] = {}
            for item in items:
                bk = item["label"].split(" ")[0]
                by_book.setdefault(bk, []).append(item)
            for bk in sorted(by_book.keys()):
                bk_items = by_book[bk]
                print(f"  {bk}: {len(bk_items)}")
                for item in bk_items[:10]:
                    detail = ""
                    if "cc" in item:
                        detail = f" cc={item['cc']}"
                    if "choices" in item:
                        detail += f" choices={item['choices']}"
                    if "prompt_snippet" in item:
                        detail += f" prompt={item['prompt_snippet'][:60]}..."
                    if "count" in item:
                        detail += f" count={item['count']}"
                    print(f"    {item['label']}{detail}")
                if len(bk_items) > 10:
                    print(f"    ... and {len(bk_items) - 10} more")
        print()

    print(f"TOTAL ISSUES: {total_issues}")
    print()

    # Per-book summary
    print("=" * 70)
    print("PER-BOOK SUMMARY")
    print("=" * 70)
    book_issues: dict[str, int] = {}
    for cat, items in issues.items():
        for item in items:
            bk = item["label"].split(" ")[0]
            book_issues[bk] = book_issues.get(bk, 0) + 1
    book_totals: dict[str, int] = {}
    for q in qs:
        bk = q["bookId"]
        book_totals[bk] = book_totals.get(bk, 0) + 1
    for bk in sorted(book_totals.keys()):
        total = book_totals[bk]
        iss = book_issues.get(bk, 0)
        pct = (total - iss) / total * 100 if total else 0
        print(f"  {bk:45s} {total:4d} qs, {iss:3d} issues ({pct:.0f}% clean)")


if __name__ == "__main__":
    main()
