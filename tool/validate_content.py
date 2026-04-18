from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path


IMAGE_REFERENCE_RE = re.compile(
    r"\[image\]"
    r"|shown\s+(?:above|below|here)\b"
    r"|shown\s+is\b"
    # "images [is/are] shown" within a short window (same phrase, not across
    # a paragraph) so generic prose like "T2-weighted images ... has been
    # shown to enhance" does not false-match.
    r"|images?(?:\s+(?:is|are))?\s+shown\b"
    # "based on <qualifier> ... images" within a single clause (no sentence
    # terminator in between).
    r"|based on\s+(?:the|these|following|diagnostic|ultrasound|mammogram|mr|mri|ct)[^.!?\n]{0,40}images?"
    r"|the following images?\b"
    r"|images?\s+available\b"
    r"|pictured here\b",
    re.IGNORECASE,
)


def _stem_group_key(question: dict) -> tuple:
    return (
        question.get("bookId"),
        question.get("chapterId"),
        question.get("sectionId"),
        question.get("stemGroup"),
    )


def _build_stem_group_index(
    questions: list[dict[str, object]],
) -> dict[tuple, list[dict]]:
    index: dict[tuple, list[dict]] = defaultdict(list)
    for q in questions:
        if q.get("stemGroup") in (None, ""):
            continue
        index[_stem_group_key(q)].append(q)
    return index


def _any_sibling_has(
    question: dict,
    stem_index: dict[tuple, list[dict]],
    fields: tuple[str, ...],
) -> bool:
    for sibling in stem_index.get(_stem_group_key(question), ()):
        if sibling.get("id") == question.get("id"):
            continue
        for field in fields:
            val = sibling.get(field) or []
            if isinstance(val, list) and any(
                isinstance(p, str) and p.strip() for p in val
            ):
                return True
    return False


def load_questions(project_root: Path) -> list[dict[str, object]]:
    questions_path = project_root / "assets" / "data" / "questions.json"
    return json.loads(questions_path.read_text(encoding="utf-8"))


def build_report(
    questions: list[dict[str, object]], project_root: Path
) -> dict[str, object]:
    issues: list[dict[str, str]] = []
    assets_root = project_root / "assets"
    stem_index = _build_stem_group_index(questions)

    for question in questions:
        question_id = str(question["id"])
        if question.get("validationRelaxed") is True:
            continue
        choices = question.get("choices", {})
        explanation = str(question.get("explanation", "")).strip()
        image_assets = question.get("imageAssets", [])
        explanation_image_assets = question.get("explanationImageAssets", [])
        prompt = str(question.get("prompt", ""))
        question_type = str(question.get("questionType", "single") or "single")
        matching_items = question.get("matchingItems") or []
        is_matching = question_type == "matching" and bool(matching_items)

        if not isinstance(explanation_image_assets, list):
            issues.append(
                {
                    "type": "bad_explanation_image_assets",
                    "questionId": question_id,
                    "message": "explanationImageAssets must be a list.",
                }
            )
            explanation_image_assets = []

        for asset_path in image_assets:
            if not isinstance(asset_path, str) or not asset_path.strip():
                continue
            resolved = (assets_root / asset_path.replace("assets/", "")).resolve()
            if not resolved.is_file():
                issues.append(
                    {
                        "type": "image_not_found",
                        "questionId": question_id,
                        "message": f"Image asset not found: {asset_path}",
                    }
                )

        for asset_path in explanation_image_assets:
            if not isinstance(asset_path, str) or not asset_path.strip():
                continue
            resolved = (assets_root / asset_path.replace("assets/", "")).resolve()
            if not resolved.is_file():
                issues.append(
                    {
                        "type": "explanation_image_not_found",
                        "questionId": question_id,
                        "message": f"Explanation image asset not found: {asset_path}",
                    }
                )

        if not isinstance(choices, dict) or len(choices) < 2:
            issues.append(
                {
                    "type": "choice_count",
                    "questionId": question_id,
                    "message": "Question does not contain at least 2 answer choices.",
                }
            )

        if not str(question.get("correctChoice", "")).strip() and not is_matching:
            issues.append(
                {
                    "type": "missing_answer",
                    "questionId": question_id,
                    "message": "Question is missing a correct answer letter.",
                }
            )

        if is_matching:
            for item in matching_items:
                if not isinstance(item, dict):
                    continue
                if not str(item.get("correctChoice", "")).strip():
                    issues.append(
                        {
                            "type": "matching_item_missing_answer",
                            "questionId": question_id,
                            "message": "Matching item is missing a correct choice.",
                        }
                    )
                    break

        if not explanation:
            issues.append(
                {
                    "type": "missing_explanation",
                    "questionId": question_id,
                    "message": "Question is missing explanation text.",
                }
            )

        prompt_mentions_figure = bool(
            IMAGE_REFERENCE_RE.search(prompt)
            or re.search(
                r"\b(below|provided|arrow|same patient)\b",
                prompt,
                re.IGNORECASE,
            )
        )
        if (
            prompt_mentions_figure
            and not image_assets
            # A multi-part follow-up (b/c/...) inherits the a-part's figures
            # via stemImageAssetsForQuestion at runtime; do not flag it here.
            and not _any_sibling_has(question, stem_index, ("imageAssets",))
        ):
            issues.append(
                {
                    "type": "missing_image",
                    "questionId": question_id,
                    "message": "Prompt suggests an image but no image asset is linked.",
                }
            )

        explanation_mentions_figure = bool(IMAGE_REFERENCE_RE.search(explanation))
        if (
            explanation_mentions_figure
            and not image_assets
            and not explanation_image_assets
            and not _any_sibling_has(
                question,
                stem_index,
                ("imageAssets", "explanationImageAssets"),
            )
        ):
            issues.append(
                {
                    "type": "missing_explanation_image",
                    "questionId": question_id,
                    "message": "Explanation suggests an image but no stem or explanation image is linked.",
                }
            )

    return {
        "questionCount": len(questions),
        "issueCount": len(issues),
        "issues": issues,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate extracted quiz content.")
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Flutter project root containing assets/data/questions.json",
    )
    parser.add_argument(
        "--fail-on-issues",
        action="store_true",
        help="Exit with code 1 if any issue is reported.",
    )
    parser.add_argument(
        "--max-issues",
        type=int,
        default=None,
        metavar="N",
        help="Exit with code 1 if issue count is greater than N (ignored when --fail-on-issues is set).",
    )
    args = parser.parse_args()

    project_root = args.project_root.expanduser().resolve()
    report = build_report(load_questions(project_root), project_root)
    report_path = project_root / "assets" / "data" / "validation_report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"Validated {report['questionCount']} questions")
    print(f"Found {report['issueCount']} issues")
    print(f"Saved validation report to {report_path}")

    issue_count = int(report["issueCount"])
    if args.fail_on_issues and issue_count > 0:
        raise SystemExit(1)
    if (
        not args.fail_on_issues
        and args.max_issues is not None
        and issue_count > args.max_issues
    ):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
