from __future__ import annotations

import argparse
import json
import re
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


def load_questions(project_root: Path) -> list[dict[str, object]]:
    questions_path = project_root / "assets" / "data" / "questions.json"
    return json.loads(questions_path.read_text(encoding="utf-8"))


def build_report(
    questions: list[dict[str, object]], project_root: Path
) -> dict[str, object]:
    issues: list[dict[str, str]] = []
    assets_root = project_root / "assets"

    for question in questions:
        question_id = str(question["id"])
        if question.get("validationRelaxed") is True:
            continue
        choices = question.get("choices", {})
        explanation = str(question.get("explanation", "")).strip()
        image_assets = question.get("imageAssets", [])
        explanation_image_assets = question.get("explanationImageAssets", [])
        prompt = str(question.get("prompt", ""))

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

        if not str(question.get("correctChoice", "")).strip():
            issues.append(
                {
                    "type": "missing_answer",
                    "questionId": question_id,
                    "message": "Question is missing a correct answer letter.",
                }
            )

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
        if prompt_mentions_figure and not image_assets:
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
