#!/usr/bin/env python3
"""
Upload all PDFs under a folder to Supabase Storage (core-review-content by default)
under reference_pdfs/<relative-path>. Writes a manifest JSON for build_reference_book_index.py.

Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.

Example:
  python tool/upload_reference_pdfs_to_supabase.py "C:/Users/nprim/Downloads/Textbooks"
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import posixpath
import sys
from pathlib import Path
from urllib import error, parse, request


PROJECT_ROOT = Path(__file__).resolve().parents[1]
BUCKET_NAME = os.environ.get("SUPABASE_STORAGE_BUCKET", "core-review-content")
# Matches lib/config/app_config.dart default when SUPABASE_URL is unset locally.
_DEFAULT_SUPABASE = "https://szerwpvldtnamhfpqmih.supabase.co"
SUPABASE_URL = os.environ.get("SUPABASE_URL", _DEFAULT_SUPABASE).rstrip("/")
SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
STORAGE_PREFIX = "reference_pdfs"


def require_upload_key() -> None:
    if not SERVICE_ROLE_KEY:
        raise RuntimeError(
            "SUPABASE_SERVICE_ROLE_KEY must be set before upload "
            f"(optional: SUPABASE_URL, defaults to {_DEFAULT_SUPABASE})."
        )


def create_bucket() -> None:
    payload = b'{"id":"%s","name":"%s","public":true}' % (
        BUCKET_NAME.encode("utf-8"),
        BUCKET_NAME.encode("utf-8"),
    )
    req = request.Request(
        f"{SUPABASE_URL}/storage/v1/bucket",
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
            "apikey": SERVICE_ROLE_KEY,
            "Content-Type": "application/json",
        },
    )
    try:
        request.urlopen(req)
    except error.HTTPError as exc:
        if exc.code not in {400, 409}:
            raise


def upload_file(file_path: Path, remote_path: str) -> None:
    content_type = (
        mimetypes.guess_type(file_path.name)[0] or "application/pdf"
    )
    req = request.Request(
        f"{SUPABASE_URL}/storage/v1/object/{BUCKET_NAME}/{remote_path}",
        data=file_path.read_bytes(),
        method="POST",
        headers={
            "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
            "apikey": SERVICE_ROLE_KEY,
            "x-upsert": "true",
            "Content-Type": content_type,
        },
    )
    try:
        request.urlopen(req)
    except error.HTTPError as exc:
        if exc.code == 409:
            req = request.Request(
                f"{SUPABASE_URL}/storage/v1/object/{BUCKET_NAME}/{remote_path}",
                data=file_path.read_bytes(),
                method="PUT",
                headers={
                    "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
                    "apikey": SERVICE_ROLE_KEY,
                    "x-upsert": "true",
                    "Content-Type": content_type,
                },
            )
            request.urlopen(req)
        else:
            raise


def public_object_url(object_path: str) -> str:
    encoded = parse.quote(object_path, safe="/")
    return (
        f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET_NAME}/{encoded}"
    )


def safe_relative_pdf(root: Path, pdf: Path) -> str:
    try:
        rel = pdf.relative_to(root)
    except ValueError as e:
        raise ValueError(f"PDF not under source root: {pdf}") from e
    posix = rel.as_posix()
    if posix.startswith("..") or "/../" in f"/{posix}/":
        raise ValueError(f"Unsafe path: {posix}")
    return posix


def discover_pdfs(root: Path) -> list[Path]:
    out: list[Path] = []
    for p in root.rglob("*.pdf"):
        if p.is_file():
            out.append(p)
    return sorted(out, key=lambda x: x.as_posix().lower())


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Upload textbook PDFs to Supabase and write URL manifest.",
    )
    parser.add_argument(
        "source_dir",
        type=Path,
        help="Folder containing PDFs (recursive).",
    )
    parser.add_argument(
        "--manifest-out",
        type=Path,
        default=PROJECT_ROOT / "tool" / "reference_pdf_upload_manifest.json",
        help="Output JSON path for build_reference_book_index.py --pdf-manifest",
    )
    args = parser.parse_args()

    require_upload_key()
    create_bucket()

    root = args.source_dir.expanduser().resolve()
    if not root.is_dir():
        raise SystemExit(f"Not a directory: {root}")

    pdfs = discover_pdfs(root)
    if not pdfs:
        raise SystemExit(f"No PDFs under {root}")

    files_map: dict[str, str] = {}
    for i, pdf in enumerate(pdfs, start=1):
        rel = safe_relative_pdf(root, pdf)
        remote_object = posixpath.join(STORAGE_PREFIX, rel.replace("\\", "/"))
        print(f"[{i}/{len(pdfs)}] {rel} -> {remote_object}")
        upload_file(pdf, remote_object)
        files_map[rel] = public_object_url(remote_object)

    manifest = {
        "version": 1,
        "bucket": BUCKET_NAME,
        "storagePrefix": STORAGE_PREFIX,
        "sourceRoot": root.as_posix(),
        "fileCount": len(files_map),
        "files": files_map,
    }
    args.manifest_out.parent.mkdir(parents=True, exist_ok=True)
    args.manifest_out.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Wrote manifest ({len(files_map)} files) to {args.manifest_out}")
    print(
        "Next: python tool/build_reference_book_index.py "
        f'"{root}" --all-pdfs --pdf-manifest "{args.manifest_out}"'
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        raise
