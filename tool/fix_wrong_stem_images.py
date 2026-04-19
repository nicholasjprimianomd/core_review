#!/usr/bin/env python3
"""Clear wrong stem imageAssets on multipart follow-up questions.

The PDF extractor sometimes attached an unrelated figure from the
follow-up part's text page (e.g. page 144 for Neuroradiology Ch.3 Q9b)
instead of letting the runtime fallback inherit the primary part's
stem image (page 143 for Q9a). The Flutter runtime
(`stemImageAssetsForQuestion` in `lib/models/book_models.dart`) treats
any non-empty `imageAssets` on the follow-up as an override, so those
wrong figures get shown in place of the real stem image.

This script finds every follow-up part (questionNumber does not end in
"a") that:

1. Is in a `stemGroup` with >=2 members inside the same book+chapter,
2. Has a primary sibling (earliest by sortOrder) that carries non-empty
   `imageAssets`,
3. Has its own `imageAssets` that diverge (different filename set) from
   the primary's,
4. Has a prompt that references the stem image in stem-style wording
   ("the following image", "the image above", "based on this image",
   "previous image", "the most likely diagnosis", etc.),
5. Has a prompt that does NOT announce a new figure ("new image",
   "additional image", "second image", "next image", "another image").

For every matched row, the script clears `imageAssets` (sets it to [])
so the runtime inherits the stem image via the existing fallback.
`explanationImageAssets` is left untouched. A report JSON is written so
the change set can be audited.

Usage:
    python tool/fix_wrong_stem_images.py --dry-run        # report only
    python tool/fix_wrong_stem_images.py --apply          # write changes
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

STEM_REFERENCES = (
    "following image",
    "above image",
    "image above",
    "image below",
    "previous image",
    "prior image",
    "same image",
    "the image",
    "this image",
    "in the image",
    "from the image",
    "in the above",
    "in the previous",
    "in the prior",
    "what is the most likely diagnosis",
    "which of the following",
    "which of these",
    "same case",
    "this case",
    "previous case",
    "this patient",
    "previous patient",
    "this question",
    "previous question",
    "the figure",
    "the study",
    "the findings",
    "the patient's imaging",
)

NEW_FIGURE_MARKERS = (
    "new image",
    "additional image",
    "second image",
    "third image",
    "fourth image",
    "next image",
    "another image",
    "new figure",
    "additional figure",
    "next figure",
    "another figure",
    "the second figure",
    "the third figure",
)


def question_number_is_follow_up(question_number: str) -> bool:
    qn = (question_number or "").strip().lower()
    if not qn:
        return False
    return not qn.endswith("a")


def asset_set(assets) -> set[str]:
    if not isinstance(assets, list):
        return set()
    return {a.strip() for a in assets if isinstance(a, str) and a.strip()}


def prompt_refers_to_stem(prompt: str) -> bool:
    p = (prompt or "").lower()
    if any(marker in p for marker in NEW_FIGURE_MARKERS):
        return False
    return any(marker in p for marker in STEM_REFERENCES)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument("--apply", action="store_true", help="Write changes to questions.json.")
    parser.add_argument("--dry-run", action="store_true", help="Report without writing.")
    parser.add_argument(
        "--report",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "tool" / "fix_wrong_stem_images_report.json",
    )
    args = parser.parse_args()

    if not args.apply and not args.dry_run:
        args.dry_run = True

    questions_path = args.project_root / "assets" / "data" / "questions.json"
    rows: list[dict] = json.loads(questions_path.read_text(encoding="utf-8"))

    groups: dict[tuple, list[dict]] = defaultdict(list)
    for q in rows:
        key = (q.get("bookId"), q.get("chapterId"), str(q.get("stemGroup") or ""))
        if not key[2]:
            continue
        groups[key].append(q)

    changes: list[dict] = []
    skipped_prompt: list[dict] = []
    skipped_no_ref: list[dict] = []

    for key, members in groups.items():
        if len(members) < 2:
            continue
        members.sort(key=lambda m: m.get("sortOrder", 0))
        primary = next((m for m in members if asset_set(m.get("imageAssets"))), None)
        if primary is None:
            continue
        primary_imgs = asset_set(primary.get("imageAssets"))
        for m in members:
            if m is primary:
                continue
            m_imgs = asset_set(m.get("imageAssets"))
            if not m_imgs or m_imgs == primary_imgs:
                continue
            qn = str(m.get("questionNumber") or "")
            if not question_number_is_follow_up(qn):
                continue
            prompt = m.get("prompt") or ""
            p_low = prompt.lower()
            if any(marker in p_low for marker in NEW_FIGURE_MARKERS):
                skipped_prompt.append(
                    {
                        "id": m.get("id"),
                        "questionNumber": qn,
                        "primaryId": primary.get("id"),
                        "reason": "prompt announces new figure",
                        "prompt": prompt,
                        "keptImageAssets": sorted(m_imgs),
                    }
                )
                continue
            if not prompt_refers_to_stem(prompt):
                skipped_no_ref.append(
                    {
                        "id": m.get("id"),
                        "questionNumber": qn,
                        "primaryId": primary.get("id"),
                        "reason": "prompt does not reference stem image",
                        "prompt": prompt,
                        "keptImageAssets": sorted(m_imgs),
                    }
                )
                continue
            changes.append(
                {
                    "id": m.get("id"),
                    "questionNumber": qn,
                    "primaryId": primary.get("id"),
                    "primaryImageAssets": sorted(primary_imgs),
                    "previousImageAssets": sorted(m_imgs),
                    "prompt": prompt,
                }
            )
            if args.apply:
                m["imageAssets"] = []

    report = {
        "applied": args.apply,
        "clearedCount": len(changes),
        "skippedNewFigureCount": len(skipped_prompt),
        "skippedNoStemReferenceCount": len(skipped_no_ref),
        "cleared": changes,
        "skippedNewFigure": skipped_prompt,
        "skippedNoStemReference": skipped_no_ref,
    }
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")

    if args.apply:
        questions_path.write_text(
            json.dumps(rows, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    print(
        "cleared={cleared} skipped_new_figure={new_fig} skipped_no_stem_ref={no_ref} applied={applied}".format(
            cleared=len(changes),
            new_fig=len(skipped_prompt),
            no_ref=len(skipped_no_ref),
            applied=args.apply,
        )
    )
    print(f"report written to: {args.report}")


if __name__ == "__main__":
    main()
