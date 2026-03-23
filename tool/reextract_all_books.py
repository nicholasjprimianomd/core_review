#!/usr/bin/env python3
"""Re-extract each Core Review PDF/epub with extract_pdf_to_json.py and merge into questions.json."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

# Allow `from epub_to_pdf import ...` when run as `python tool/reextract_all_books.py`
_TOOL = Path(__file__).resolve().parent
if str(_TOOL) not in sys.path:
    sys.path.insert(0, str(_TOOL))

def find_source_file(
    source_name: str,
    extra_paths: dict[str, Path],
    search_dirs: list[Path],
) -> Path | None:
    if source_name in extra_paths:
        p = extra_paths[source_name]
        if p.is_file():
            return p
    for d in search_dirs:
        if not d.is_dir():
            continue
        direct = d / source_name
        if direct.is_file():
            return direct
        lowered = source_name.lower()
        for f in d.iterdir():
            if f.is_file() and f.name.lower() == lowered:
                return f
    return None


def resolve_extract_path(source_path: Path) -> Path:
    """PDFs are passed through. EPUBs are opened natively by PyMuPDF (preserves TOC; EPUB->PDF loses bookmarks)."""
    suf = source_path.suffix.lower()
    if suf in {".pdf", ".epub"}:
        return source_path
    raise ValueError(f"Unsupported source type: {source_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Re-extract Core Review sources into assets/data/questions.json.",
    )
    parser.add_argument(
        "--only",
        nargs="+",
        metavar="BOOK_ID",
        help="Only re-extract these book ids (e.g. breast-imaging ultrasound). "
        "Other books keep existing rows in questions.json.",
    )
    args = parser.parse_args()
    only_ids: set[str] | None = set(args.only) if args.only else None

    repo = Path(__file__).resolve().parents[1]
    books_path = repo / "assets" / "data" / "books.json"
    questions_path = repo / "assets" / "data" / "questions.json"
    dest_images = repo / "assets" / "book_images"
    extract_script = repo / "tool" / "extract_pdf_to_json.py"

    search_dirs = [
        Path(r"C:\Users\nprim\Downloads\OneDrive_1_3-13-2026"),
        Path(r"C:\Users\nprim\Downloads"),
        repo / "tool" / "sources",
    ]

    # Explicit overrides (optional). Keys must match books.json `sourceFileName` exactly.
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
        "Breast Imaging A Core Review.epub": Path(
            r"C:\Users\nprim\Downloads\OneDrive_1_3-13-2026\Breast Imaging A Core Review.epub"
        ),
        "Ultrasound A Core Review.epub": Path(
            r"C:\Users\nprim\Downloads\OneDrive_1_3-13-2026\Ultrasound A Core Review.epub"
        ),
    }

    books: list[dict] = json.loads(books_path.read_text(encoding="utf-8"))
    books_sorted = sorted(books, key=lambda b: b["order"])
    existing_questions: list[dict] = json.loads(questions_path.read_text(encoding="utf-8"))
    existing_by_book: dict[str, list[dict]] = {}
    for q in existing_questions:
        bid = q.get("bookId", "")
        existing_by_book.setdefault(bid, []).append(q)

    if only_ids is not None:
        unknown = only_ids - {b["id"] for b in books}
        if unknown:
            raise SystemExit(f"Unknown book id(s): {sorted(unknown)}")

    temp_root = repo / ".reextract_workspace"
    temp_root.mkdir(exist_ok=True)

    merged: list[dict] = []
    skipped: list[str] = []
    extracted_ids: list[str] = []

    for book in books_sorted:
        bid = book["id"]
        src_name = book["sourceFileName"]

        if only_ids is not None and bid not in only_ids:
            merged.extend(
                sorted(
                    existing_by_book.get(bid, []),
                    key=lambda q: (q.get("chapterNumber", 0), q.get("order", 0)),
                )
            )
            continue

        src_path = find_source_file(src_name, extra_paths, search_dirs)
        if src_path is None:
            skipped.append(f"{bid} (missing: {src_name})")
            merged.extend(
                sorted(
                    existing_by_book.get(bid, []),
                    key=lambda q: (q.get("chapterNumber", 0), q.get("order", 0)),
                )
            )
            continue

        try:
            extract_input = resolve_extract_path(src_path)
        except Exception as exc:
            skipped.append(f"{bid} (failed: {src_path.name}: {exc})")
            merged.extend(
                sorted(
                    existing_by_book.get(bid, []),
                    key=lambda q: (q.get("chapterNumber", 0), q.get("order", 0)),
                )
            )
            continue

        work = temp_root / bid.replace("/", "_")
        if work.exists():
            shutil.rmtree(work)
        work.mkdir(parents=True)
        (work / "assets" / "data").mkdir(parents=True)

        print(f"Extracting {bid} from {extract_input.name} ...", flush=True)
        subprocess.run(
            [
                sys.executable,
                str(extract_script),
                "--project-root",
                str(work),
                "--inputs",
                str(extract_input),
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
