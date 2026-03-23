#!/usr/bin/env python3
"""Re-extract each Core Review PDF/epub with extract_pdf_to_json.py and merge into questions.json."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> None:
    repo = Path(__file__).resolve().parents[1]
    books_path = repo / "assets" / "data" / "books.json"
    questions_path = repo / "assets" / "data" / "questions.json"
    dest_images = repo / "assets" / "book_images"
    extract_script = repo / "tool" / "extract_pdf_to_json.py"

    # Paths verified on developer machine; adjust if files move.
    extra_paths: dict[str, Path] = {
        "Thoracic Imaging - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\Thoracic Imaging - A Core Review.pdf"
        ),
        "Cardiac - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\OneDrive_1_3-13-2026\Cardiac - A Core Review.pdf"
        ),
        "Gastrointestinal - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\OneDrive_1_3-13-2026\Gastrointestinal - A Core Review.pdf"
        ),
        "Genitourinary - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\OneDrive_1_3-13-2026\Genitourinary - A Core Review.pdf"
        ),
        "Musculoskeletal Imaging - A Core Review- (2015).pdf": Path(
            r"C:\Users\nprim\Downloads\OneDrive_1_3-13-2026\Musculoskeletal Imaging - A Core Review- (2015).pdf"
        ),
        "Neuroradiology - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\OneDrive_1_3-13-2026\Neuroradiology - A Core Review.pdf"
        ),
        "Nuclear Medicine - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\OneDrive_1_3-13-2026\Nuclear Medicine - A Core Review.pdf"
        ),
        "Pediatric Imaging - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\OneDrive_1_3-13-2026\Pediatric Imaging - A Core Review.pdf"
        ),
        "Vascular and Interventional Radiology - Unknown.pdf": Path(
            r"C:\Users\nprim\Downloads\OneDrive_1_3-13-2026\Vascular and Interventional Radiology - Unknown.pdf"
        ),
    }

    books: list[dict] = json.loads(books_path.read_text(encoding="utf-8"))
    books_sorted = sorted(books, key=lambda b: b["order"])
    prod_questions: list[dict] = json.loads(questions_path.read_text(encoding="utf-8"))
    prod_by_book: dict[str, list[dict]] = {}
    for q in prod_questions:
        bid = q.get("bookId", "")
        prod_by_book.setdefault(bid, []).append(q)

    temp_root = repo / ".reextract_workspace"
    temp_root.mkdir(exist_ok=True)

    merged: list[dict] = []
    skipped: list[str] = []
    extracted_ids: list[str] = []

    for book in books_sorted:
        bid = book["id"]
        src_name = book["sourceFileName"]
        src_path = extra_paths.get(src_name)
        if src_path is None or not src_path.is_file():
            skipped.append(f"{bid} (missing: {src_name})")
            merged.extend(
                sorted(
                    prod_by_book.get(bid, []),
                    key=lambda q: (q.get("chapterNumber", 0), q.get("order", 0)),
                )
            )
            continue

        work = temp_root / bid.replace("/", "_")
        if work.exists():
            shutil.rmtree(work)
        work.mkdir(parents=True)
        (work / "assets" / "data").mkdir(parents=True)

        print(f"Extracting {bid} from {src_path.name} ...", flush=True)
        subprocess.run(
            [
                sys.executable,
                str(extract_script),
                "--project-root",
                str(work),
                "--inputs",
                str(src_path),
            ],
            cwd=repo,
            check=True,
        )

        out_q = work / "assets" / "data" / "questions.json"
        chunk = json.loads(out_q.read_text(encoding="utf-8"))
        merged.extend(chunk)
        extracted_ids.append(bid)

        img_src = work / "assets" / "book_images"
        if img_src.is_dir():
            dest_images.mkdir(parents=True, exist_ok=True)
            for png in img_src.glob("*.png"):
                shutil.copy2(png, dest_images / png.name)

    for i, q in enumerate(merged, start=1):
        q["sortOrder"] = i

    questions_path.write_text(json.dumps(merged, indent=2), encoding="utf-8")

    print()
    print(f"Wrote {len(merged)} questions to {questions_path}")
    print(f"Re-extracted books ({len(extracted_ids)}): {', '.join(extracted_ids)}")
    if skipped:
        print(f"Kept production data for ({len(skipped)}): {skipped}")


if __name__ == "__main__":
    main()
