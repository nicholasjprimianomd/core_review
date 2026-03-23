#!/usr/bin/env python3
"""Convert EPUB to PDF using PyMuPDF (MuPDF).

For Core Review catalog extraction, prefer passing the .epub to extract_pdf_to_json.py
directly: conversion to PDF drops TOC bookmarks and breaks chapter detection.
This utility remains useful for human-readable PDF output.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import fitz


def epub_to_pdf(epub_path: Path, pdf_path: Path) -> None:
    epub_path = epub_path.expanduser().resolve()
    pdf_path = pdf_path.expanduser().resolve()
    pdf_path.parent.mkdir(parents=True, exist_ok=True)

    book = fitz.open(epub_path)
    try:
        pdf_bytes = book.convert_to_pdf()
    finally:
        book.close()

    pdf = fitz.open(stream=pdf_bytes, filetype="pdf")
    try:
        pdf.save(pdf_path)
    finally:
        pdf.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert EPUB to PDF via PyMuPDF.")
    parser.add_argument("epub", type=Path, help="Input .epub file")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Output .pdf path (default: same name as epub with .pdf)",
    )
    args = parser.parse_args()
    out = args.output
    if out is None:
        out = args.epub.with_suffix(".pdf")
    epub_to_pdf(args.epub, out)
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
