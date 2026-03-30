#!/usr/bin/env python3
"""Compare extracted MSK questions.json to production; optionally merge MSK + images."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


def load_msk(path: Path) -> dict[str, dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return {q["id"]: q for q in data if q.get("bookId") == "musculoskeletal-imaging"}


def normalize(obj: object) -> str:
    return json.dumps(obj, sort_keys=True, ensure_ascii=False)


def main() -> None:
    parser = argparse.ArgumentParser(description="MSK extract vs production diff/merge.")
    parser.add_argument(
        "--production-questions",
        type=Path,
        default=Path("assets/data/questions.json"),
    )
    parser.add_argument(
        "--extracted-questions",
        type=Path,
        required=True,
        help="Path to questions.json from extract_pdf_to_json (MSK-only run).",
    )
    parser.add_argument(
        "--extracted-book-images",
        type=Path,
        required=True,
        help="Path to extracted assets/book_images directory.",
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=Path("tool/msk_diff_report.json"),
    )
    parser.add_argument(
        "--merge",
        action="store_true",
        help="Replace MSK entries in production with extracted; copy PNGs.",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path("."),
    )
    args = parser.parse_args()
    root = args.project_root.expanduser().resolve()

    prod_path = (root / args.production_questions).resolve()
    ext_q_path = args.extracted_questions.expanduser().resolve()

    prod_msk = load_msk(prod_path)
    ext_msk = load_msk(ext_q_path)

    prod_ids = set(prod_msk)
    ext_ids = set(ext_msk)
    only_prod = sorted(prod_ids - ext_ids)
    only_ext = sorted(ext_ids - prod_ids)

    fields = (
        "prompt",
        "choices",
        "correctChoice",
        "explanation",
        "references",
        "imageAssets",
        "explanationImageAssets",
    )
    diffs: list[dict[str, object]] = []
    for qid in sorted(prod_ids & ext_ids):
        p, e = prod_msk[qid], ext_msk[qid]
        changed: dict[str, tuple[str, str]] = {}
        for f in fields:
            pv, ev = p.get(f), e.get(f)
            if normalize(pv) != normalize(ev):
                changed[f] = (normalize(pv), normalize(ev))
        if changed:
            diffs.append({"id": qid, "fields": list(changed.keys())})

    report = {
        "productionCount": len(prod_msk),
        "extractedCount": len(ext_msk),
        "onlyInProduction": only_prod,
        "onlyInExtracted": only_ext,
        "diffCount": len(diffs),
        "diffs": diffs,
    }
    report_path = (root / args.report).resolve() if not args.report.is_absolute() else args.report
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({k: report[k] for k in report if k != "diffs"}, indent=2))
    print(f"Wrote {report_path}")

    if args.merge:
        ext_img = args.extracted_book_images.expanduser().resolve()
        dest_img = root / "assets" / "book_images"
        dest_img.mkdir(parents=True, exist_ok=True)

        all_q = json.loads(prod_path.read_text(encoding="utf-8"))
        ext_by_id = ext_msk
        new_list: list[dict] = []
        replaced = 0
        for q in all_q:
            if q.get("bookId") == "musculoskeletal-imaging":
                eid = q["id"]
                if eid in ext_by_id:
                    new_list.append(ext_by_id[eid])
                    replaced += 1
                else:
                    new_list.append(q)
            else:
                new_list.append(q)

        if replaced != len(ext_msk):
            raise SystemExit(
                f"merge mismatch: replaced {replaced}, expected {len(ext_msk)}"
            )

        prod_path.write_text(json.dumps(new_list, indent=2), encoding="utf-8")
        print(f"Merged {replaced} MSK questions into {prod_path}")

        for png in sorted(ext_img.glob("musculoskeletal-imaging_*.png")):
            shutil.copy2(png, dest_img / png.name)
        print(f"Copied MSK PNGs from {ext_img} to {dest_img}")


if __name__ == "__main__":
    main()
