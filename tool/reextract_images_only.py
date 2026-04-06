#!/usr/bin/env python3
"""Re-extract images only: runs the full extractor per book, then replaces ONLY
imageAssets / explanationImageAssets in the production questions.json.

All other fields (id, prompt, choices, correctChoice, explanation, references,
stemGroup, sortOrder, etc.) are preserved exactly.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

_TOOL = Path(__file__).resolve().parent
if str(_TOOL) not in sys.path:
    sys.path.insert(0, str(_TOOL))

from safe_merge_questions import replace_images_only


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
    suf = source_path.suffix.lower()
    if suf in {".pdf", ".epub"}:
        return source_path
    raise ValueError(f"Unsupported source type: {source_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Re-extract images for all (or selected) books and replace "
        "imageAssets / explanationImageAssets in questions.json without "
        "touching any other field.",
    )
    parser.add_argument(
        "--only",
        nargs="+",
        metavar="BOOK_ID",
        help="Only re-extract images for these book ids. Others keep existing image fields.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Extract and report counts but do not write questions.json or copy images.",
    )
    args = parser.parse_args()
    only_ids: set[str] | None = set(args.only) if args.only else None

    repo = Path(__file__).resolve().parents[1]
    books_path = repo / "assets" / "data" / "books.json"
    questions_path = repo / "assets" / "data" / "questions.json"
    dest_images = repo / "assets" / "book_images"
    extract_script = repo / "tool" / "extract_pdf_to_json.py"

    search_dirs = [
        Path(r"C:\Users\nprim\Downloads\Textbooks"),
        Path(r"C:\Users\nprim\Downloads"),
        repo / "tool" / "sources",
    ]

    extra_paths: dict[str, Path] = {
        "Thoracic Imaging - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\Thoracic Imaging - A Core Review.pdf"
        ),
        "Cardiac - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\Textbooks\Cardiac - A Core Review.pdf"
        ),
        "Gastrointestinal - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\Textbooks\Gastrointestinal - A Core Review.pdf"
        ),
        "Genitourinary - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\Textbooks\Genitourinary - A Core Review.pdf"
        ),
        "Musculoskeletal Imaging - A Core Review- (2015).pdf": Path(
            r"C:\Users\nprim\Downloads\Textbooks\Musculoskeletal Imaging - A Core Review- (2015).pdf"
        ),
        "Neuroradiology - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\Textbooks\Neuroradiology - A Core Review.pdf"
        ),
        "Nuclear Medicine - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\Textbooks\Nuclear Medicine - A Core Review.pdf"
        ),
        "Pediatric Imaging - A Core Review.pdf": Path(
            r"C:\Users\nprim\Downloads\Textbooks\Pediatric Imaging - A Core Review.pdf"
        ),
        "Vascular and Interventional Radiology - Unknown.pdf": Path(
            r"C:\Users\nprim\Downloads\Textbooks\Vascular and Interventional Radiology - Unknown.pdf"
        ),
        "Breast Imaging A Core Review.epub": Path(
            r"C:\Users\nprim\Downloads\Textbooks\Breast Imaging A Core Review.pdf"
        ),
        "Ultrasound A Core Review.epub": Path(
            r"C:\Users\nprim\Downloads\Textbooks\Ultrasound A Core Review.pdf"
        ),
    }

    books: list[dict] = json.loads(books_path.read_text(encoding="utf-8"))
    books_sorted = sorted(books, key=lambda b: b["order"])
    production_questions: list[dict] = json.loads(
        questions_path.read_text(encoding="utf-8")
    )

    if only_ids is not None:
        unknown = only_ids - {b["id"] for b in books}
        if unknown:
            raise SystemExit(f"Unknown book id(s): {sorted(unknown)}")

    temp_root = repo / ".reextract_workspace"
    temp_root.mkdir(exist_ok=True)

    extracted_images_by_book: dict[str, list[dict]] = {}
    image_files_by_book: dict[str, list[Path]] = {}
    skipped: list[str] = []
    extracted_ids: list[str] = []

    for book in books_sorted:
        bid = book["id"]
        src_name = book["sourceFileName"]

        if only_ids is not None and bid not in only_ids:
            continue

        src_path = find_source_file(src_name, extra_paths, search_dirs)
        if src_path is None:
            skipped.append(f"{bid} (missing: {src_name})")
            continue

        try:
            extract_input = resolve_extract_path(src_path)
        except Exception as exc:
            skipped.append(f"{bid} (failed: {src_path.name}: {exc})")
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
        extracted_images_by_book[bid] = chunk
        extracted_ids.append(bid)

        img_src = work / "assets" / "book_images"
        book_images: list[Path] = []
        if img_src.is_dir():
            for pattern in ("*.png", "*.jpg", "*.jpeg", "*.webp"):
                book_images.extend(img_src.glob(pattern))
        image_files_by_book[bid] = book_images

    prod_by_book: dict[str, list[dict]] = {}
    for q in production_questions:
        bid = q.get("bookId", "")
        prod_by_book.setdefault(bid, []).append(q)

    old_image_refs: set[str] = set()
    for q in production_questions:
        for p in q.get("imageAssets") or []:
            if isinstance(p, str):
                old_image_refs.add(p)
        for p in q.get("explanationImageAssets") or []:
            if isinstance(p, str):
                old_image_refs.add(p)

    updated: list[dict] = []
    for bid_key in sorted(
        {q.get("bookId", "") for q in production_questions},
        key=lambda b: next(
            (bk["order"] for bk in books_sorted if bk["id"] == b), 999
        ),
    ):
        book_rows = prod_by_book.get(bid_key, [])
        if bid_key in extracted_images_by_book:
            merged = replace_images_only(book_rows, extracted_images_by_book[bid_key])
            updated.extend(merged)
        else:
            updated.extend(book_rows)

    for i, q in enumerate(updated, start=1):
        q["sortOrder"] = i

    new_image_refs: set[str] = set()
    for q in updated:
        for p in q.get("imageAssets") or []:
            if isinstance(p, str):
                new_image_refs.add(p)
        for p in q.get("explanationImageAssets") or []:
            if isinstance(p, str):
                new_image_refs.add(p)

    stats_by_book: dict[str, dict[str, int]] = {}
    for q in updated:
        bid = q.get("bookId", "")
        s = stats_by_book.setdefault(bid, {"stem": 0, "expl": 0, "total": 0})
        s["stem"] += len(q.get("imageAssets") or [])
        s["expl"] += len(q.get("explanationImageAssets") or [])
        s["total"] += 1

    print()
    print("=== Image replacement summary ===")
    for bid, s in sorted(stats_by_book.items()):
        print(
            f"  {bid}: {s['total']} questions, "
            f"{s['stem']} stem images, {s['expl']} explanation images"
        )
    print(f"  Total questions: {len(updated)}")
    print(f"  Total unique image refs (old): {len(old_image_refs)}")
    print(f"  Total unique image refs (new): {len(new_image_refs)}")
    print(f"  Re-extracted: {', '.join(extracted_ids)}")
    if skipped:
        print(f"  Skipped: {skipped}")

    if args.dry_run:
        print("\nDry run -- no files written.")
        return

    questions_path.write_text(json.dumps(updated, indent=2), encoding="utf-8")
    print(f"\nWrote {len(updated)} questions to {questions_path}")

    dest_images.mkdir(parents=True, exist_ok=True)
    copied = 0
    for bid, files in image_files_by_book.items():
        for img in files:
            shutil.copy2(img, dest_images / img.name)
            copied += 1
    print(f"Copied {copied} image files to {dest_images}")

    orphaned_basenames: set[str] = set()
    for ref in old_image_refs - new_image_refs:
        basename = Path(ref).name
        orphaned_basenames.add(basename)

    removed = 0
    for basename in orphaned_basenames:
        p = dest_images / basename
        if p.exists():
            p.unlink()
            removed += 1
    if removed:
        print(f"Removed {removed} orphaned image files")


if __name__ == "__main__":
    main()
