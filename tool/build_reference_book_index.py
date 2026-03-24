#!/usr/bin/env python3
"""
Build api/reference_books_index.json from Crack the Core / War Machine PDFs.

Run on a machine that has the PDFs, then deploy (commit the JSON or upload with deploy).
Example:
  python tool/build_reference_book_index.py "C:/Users/nprim/Downloads/OneDrive_2026-03-24/Crack the Core PDF"
"""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

try:
    import fitz
except ImportError as e:
    raise SystemExit("Install PyMuPDF: pip install pymupdf") from e

# Only index PDFs whose name suggests these books (case-insensitive).
# "ctc" matches Crack the Core files often named "CTC 1 …", "CTC 2 …".
NAME_KEYWORDS = ("crack", "war", "machine", "core", "ctc")

MAX_TEXT_PER_PAGE = 900
PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = PROJECT_ROOT / "api" / "reference_books_index.json"


def _should_include_pdf(name: str) -> bool:
    lower = name.lower()
    if not lower.endswith(".pdf"):
        return False
    return any(k in lower for k in NAME_KEYWORDS)


def _extract_pages(pdf_path: Path, book_label: str) -> list[dict]:
    out: list[dict] = []
    doc = fitz.open(pdf_path)
    try:
        for i in range(doc.page_count):
            page = doc.load_page(i)
            text = page.get_text("text") or ""
            text = re.sub(r"\s+", " ", text).strip()
            if len(text) > MAX_TEXT_PER_PAGE:
                text = text[:MAX_TEXT_PER_PAGE] + "…"
            out.append(
                {
                    "bookLabel": book_label,
                    "fileName": pdf_path.name,
                    "page": i + 1,
                    "text": text,
                }
            )
    finally:
        doc.close()
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "source_dir",
        type=Path,
        nargs="?",
        default=Path(r"C:\Users\nprim\Downloads\OneDrive_2026-03-24\Crack the Core PDF"),
        help="Folder containing Crack the Core / War Machine PDFs",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUT,
        help=f"Output JSON (default: {DEFAULT_OUT})",
    )
    args = parser.parse_args()
    root = args.source_dir.expanduser().resolve()
    if not root.is_dir():
        raise SystemExit(f"Not a directory: {root}")

    pdfs: list[Path] = []
    for p in root.rglob("*.pdf"):
        if p.is_file() and _should_include_pdf(p.name):
            pdfs.append(p)

    if not pdfs:
        raise SystemExit(
            f"No matching PDFs under {root}. Expected names containing "
            f"one of: {NAME_KEYWORDS}"
        )

    pages: list[dict] = []
    for pdf in sorted(pdfs, key=lambda x: x.as_posix().lower()):
        label = pdf.stem.replace("_", " ")
        pages.extend(_extract_pages(pdf, label))

    payload = {
        "version": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sourceRoot": root.as_posix(),
        "pageCount": len(pages),
        "pages": pages,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"Wrote {len(pages)} page records from {len(pdfs)} PDF(s) to {args.output}")


if __name__ == "__main__":
    main()
