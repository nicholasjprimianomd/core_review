#!/usr/bin/env python3
"""
Build api/reference_books_index.json from Crack the Core / War Machine PDFs.

Run on a machine that has the PDFs, then deploy (commit the JSON or upload with deploy).
Examples:
  python tool/build_reference_book_index.py "path/to/Crack the Core PDF"
  python tool/build_reference_book_index.py "path/to/Textbooks" --all-pdfs --pdf-manifest tool/reference_pdf_upload_manifest.json
"""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

STORAGE_PREFIX = "reference_pdfs"

try:
    import fitz
except ImportError as e:
    raise SystemExit("Install PyMuPDF: pip install pymupdf") from e

# Only index PDFs whose name suggests these books (case-insensitive).
# "ctc" matches Crack the Core files often named "CTC 1 …", "CTC 2 …".
NAME_KEYWORDS = ("crack", "war", "machine", "core", "ctc")

# Per PDF page cap when indexing (raise and rebuild if you need more text per page).
MAX_TEXT_PER_PAGE = 12000
PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = PROJECT_ROOT / "api" / "reference_books_index.json"


def _normalize_pdf_text(text: str) -> str:
    """Keep line breaks; collapse spaces within each line; trim tall blank stacks."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines: list[str] = []
    for line in text.split("\n"):
        lines.append(" ".join(line.split()))
    text = "\n".join(lines)
    text = re.sub(r"\n{4,}", "\n\n\n", text)
    return text.strip()


def _should_include_pdf(name: str, include_all_pdfs: bool) -> bool:
    lower = name.lower()
    if not lower.endswith(".pdf"):
        return False
    if include_all_pdfs:
        return True
    return any(k in lower for k in NAME_KEYWORDS)


def _extract_pages(pdf_path: Path, book_label: str, file_name: str) -> list[dict]:
    out: list[dict] = []
    doc = fitz.open(pdf_path)
    try:
        for i in range(doc.page_count):
            page = doc.load_page(i)
            text = page.get_text("text") or ""
            text = _normalize_pdf_text(text)
            if len(text) > MAX_TEXT_PER_PAGE:
                cut = text[: MAX_TEXT_PER_PAGE + 1]
                last_nl = cut.rfind("\n")
                if last_nl > int(MAX_TEXT_PER_PAGE * 0.82):
                    text = cut[:last_nl].rstrip() + "…"
                else:
                    text = cut[:MAX_TEXT_PER_PAGE].rstrip() + "…"
            out.append(
                {
                    "bookLabel": book_label,
                    "fileName": file_name,
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
    parser.add_argument(
        "--all-pdfs",
        action="store_true",
        help="Index every PDF under the source folder (not only Crack/War Machine name keywords).",
    )
    parser.add_argument(
        "--pdf-manifest",
        type=Path,
        default=None,
        help="Path to reference_pdf_upload_manifest.json from upload_reference_pdfs_to_supabase.py; "
        "embeds pdfUrlsByFileName in the index.",
    )
    parser.add_argument(
        "--public-bucket-root",
        type=str,
        default=None,
        help="Public object root without trailing slash, e.g. "
        "https://PROJECT.supabase.co/storage/v1/object/public/BUCKET — builds pdfUrlsByFileName "
        f'as {STORAGE_PREFIX}/<relative.pdf> (same layout as upload_reference_pdfs_to_supabase.py). '
        "Ignored when --pdf-manifest is set.",
    )
    args = parser.parse_args()
    root = args.source_dir.expanduser().resolve()
    if not root.is_dir():
        raise SystemExit(f"Not a directory: {root}")

    pdfs: list[Path] = []
    for p in root.rglob("*.pdf"):
        if p.is_file() and _should_include_pdf(p.name, args.all_pdfs):
            pdfs.append(p)

    if not pdfs:
        hint = (
            f"Try --all-pdfs, or use file names containing one of: {NAME_KEYWORDS}"
        )
        raise SystemExit(f"No matching PDFs under {root}. {hint}")

    pdf_urls_by_file_name: dict[str, str] | None = None
    if args.pdf_manifest is not None:
        raw_manifest = json.loads(
            args.pdf_manifest.expanduser().resolve().read_text(encoding="utf-8")
        )
        files = raw_manifest.get("files")
        if not isinstance(files, dict):
            raise SystemExit("--pdf-manifest must contain a JSON object 'files' map.")
        pdf_urls_by_file_name = {str(k): str(v) for k, v in files.items()}
    elif args.public_bucket_root is not None:
        root_url = args.public_bucket_root.strip().rstrip("/")
        pdf_urls_by_file_name = {}
        for pdf in sorted(pdfs, key=lambda x: x.as_posix().lower()):
            rel = pdf.relative_to(root).as_posix()
            object_path = f"{STORAGE_PREFIX}/{rel}"
            encoded = quote(object_path, safe="/")
            pdf_urls_by_file_name[rel] = f"{root_url}/{encoded}"

    pages: list[dict] = []
    for pdf in sorted(pdfs, key=lambda x: x.as_posix().lower()):
        rel = pdf.relative_to(root).as_posix()
        label = rel
        if label.lower().endswith(".pdf"):
            label = label[:-4]
        label = label.replace("_", " ").replace("/", " · ")
        pages.extend(_extract_pages(pdf, label, rel))

    payload = {
        "version": 2 if pdf_urls_by_file_name else 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sourceRoot": root.as_posix(),
        "pageCount": len(pages),
        "pages": pages,
    }
    if pdf_urls_by_file_name:
        payload["pdfUrlsByFileName"] = pdf_urls_by_file_name
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"Wrote {len(pages)} page records from {len(pdfs)} PDF(s) to {args.output}")


if __name__ == "__main__":
    main()
