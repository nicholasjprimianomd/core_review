#!/usr/bin/env python3
"""
Upload all PDFs under a folder to Supabase Storage (core-review-content by default).
Objects are stored as reference_pdfs/<sha256>.pdf by default so commas, parentheses, etc.
in file names do not break Storage. Manifest maps original relative paths to public URLs —
run build_reference_book_index.py with --pdf-manifest afterward.

Files larger than 5 MiB use Supabase TUS resumable uploads (6 MiB chunks) via the direct
storage hostname.

Hosted Free tier: each object is capped at 50 MiB (cannot be raised without upgrading).
Larger PDFs will get 413 until you upgrade (Pro+), split/compress files, host them elsewhere,
or pass --max-file-mib to skip only the oversized ones.

Each upload deletes any existing object at the same path first so re-runs and TUS
replace old files without 409 conflicts.

Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.

Example:
  python tool/upload_reference_pdfs_to_supabase.py "C:/Users/nprim/Downloads/Textbooks"
"""

from __future__ import annotations

import argparse
import base64
import hashlib
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

# Single-request uploads hit platform limits; Supabase recommends TUS for files over ~6MB.
_SIMPLE_UPLOAD_MAX_BYTES = 5 * 1024 * 1024
_TUS_CHUNK_SIZE = 6 * 1024 * 1024
_HTTP_TIMEOUT_SEC = 600

# Hosted Supabase Free plan: global file size limit cannot exceed 50 MiB per object.
# https://supabase.com/docs/guides/storage/uploads/file-limits
_SUPABASE_FREE_PLAN_MAX_FILE_BYTES = 50 * 1024 * 1024


def _human_bytes(n: int) -> str:
    if n < 1024:
        return f"{n} B"
    if n < 1024 * 1024:
        return f"{n / 1024:.1f} KB"
    if n < 1024 * 1024 * 1024:
        return f"{n / (1024 * 1024):.1f} MB"
    return f"{n / (1024 * 1024 * 1024):.2f} GB"


def _print_413_guidance(file_path: Path, byte_size: int) -> None:
    print("", file=sys.stderr)
    print("Upload failed: payload too large (413). TUS chunking does not bypass per-file caps.",
          file=sys.stderr)
    print(f"  File: {file_path.name}", file=sys.stderr)
    print(f"  Size: {_human_bytes(byte_size)} ({byte_size} bytes)", file=sys.stderr)
    print("", file=sys.stderr)
    print("Supabase hosted Free plan: max 50 MiB per object (dashboard cannot go higher).",
          file=sys.stderr)
    print("  Pro+ plans: raise 'Global file size limit' under Storage settings (up to 500 GB).",
          file=sys.stderr)
    print("  Dashboard: https://supabase.com/dashboard/project/_/storage/settings",
          file=sys.stderr)
    print("  Docs: https://supabase.com/docs/guides/storage/uploads/file-limits",
          file=sys.stderr)
    print("", file=sys.stderr)
    print("Options: upgrade the project, split/compress PDFs, host huge files elsewhere,",
          file=sys.stderr)
    print("or re-run with --max-file-mib to skip oversized files (they will not be in Storage).",
          file=sys.stderr)
    print("", file=sys.stderr)


def require_upload_key() -> None:
    if not SERVICE_ROLE_KEY:
        raise RuntimeError(
            "SUPABASE_SERVICE_ROLE_KEY must be set before upload "
            f"(optional: SUPABASE_URL, defaults to {_DEFAULT_SUPABASE})."
        )


def _encoded_object_path_for_url(remote_path: str) -> str:
    """Encode object key for HTTP path (spaces and special chars break urllib otherwise)."""
    normalized = remote_path.replace("\\", "/")
    return parse.quote(normalized, safe="/")


def _storage_upload_url(remote_path: str) -> str:
    encoded = _encoded_object_path_for_url(remote_path)
    return f"{SUPABASE_URL}/storage/v1/object/{BUCKET_NAME}/{encoded}"


def _http_error_body(exc: error.HTTPError) -> str:
    try:
        if exc.fp is None:
            return ""
        raw = exc.read()
        return raw.decode("utf-8", errors="replace").strip()
    except Exception:
        return ""


def _response_indicates_payload_too_large(http_code: int, body: str) -> bool:
    if http_code == 413:
        return True
    if "Payload too large" in body or "payload too large" in body.lower():
        return True
    try:
        payload = json.loads(body)
        if str(payload.get("statusCode")) == "413":
            return True
    except Exception:
        pass
    return False


def _resumable_upload_endpoint() -> str:
    """Prefer direct storage hostname (better for large uploads per Supabase docs)."""
    parsed = parse.urlparse(SUPABASE_URL)
    host = parsed.hostname or ""
    if host.endswith(".supabase.co") and ".storage." not in host:
        project = host[: -len(".supabase.co")]
        return f"{parsed.scheme}://{project}.storage.supabase.co/storage/v1/upload/resumable"
    return f"{SUPABASE_URL}/storage/v1/upload/resumable"


def _tus_upload_metadata(file_path: Path, remote_path: str) -> str:
    content_type = (
        mimetypes.guess_type(file_path.name)[0] or "application/pdf"
    )
    object_name = remote_path.replace("\\", "/")

    def enc(key: str, value: str) -> str:
        b = base64.b64encode(value.encode("utf-8")).decode("ascii")
        return f"{key} {b}"

    return ",".join(
        [
            enc("bucketName", BUCKET_NAME),
            enc("objectName", object_name),
            enc("contentType", content_type),
            enc("cacheControl", "3600"),
        ]
    )


def upload_file_resumable(file_path: Path, remote_path: str) -> None:
    """TUS resumable upload (6MB chunks). Required for large PDFs."""
    endpoint = _resumable_upload_endpoint()
    total = file_path.stat().st_size
    metadata = _tus_upload_metadata(file_path, remote_path)
    create_req = request.Request(
        endpoint,
        method="POST",
        data=b"",
        headers={
            "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
            "apikey": SERVICE_ROLE_KEY,
            "x-upsert": "true",
            "Tus-Resumable": "1.0.0",
            "Upload-Length": str(total),
            "Upload-Metadata": metadata,
            "Content-Length": "0",
        },
    )
    try:
        with request.urlopen(create_req, timeout=_HTTP_TIMEOUT_SEC) as resp:
            location = resp.headers.get("Location") or resp.headers.get("location")
    except error.HTTPError as exc:
        body = _http_error_body(exc)
        if body:
            print(f"TUS create HTTP {exc.code}: {body}", file=sys.stderr)
        if _response_indicates_payload_too_large(exc.code, body):
            _print_413_guidance(file_path, total)
        raise
    if not location:
        raise RuntimeError("TUS create response missing Location header")

    upload_url = parse.urljoin(endpoint, location)
    offset = 0
    with file_path.open("rb") as f:
        while offset < total:
            chunk = f.read(_TUS_CHUNK_SIZE)
            if not chunk:
                break
            patch_req = request.Request(
                upload_url,
                method="PATCH",
                data=chunk,
                headers={
                    "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
                    "apikey": SERVICE_ROLE_KEY,
                    "Tus-Resumable": "1.0.0",
                    "Upload-Offset": str(offset),
                    "Content-Type": "application/offset+octet-stream",
                    "Content-Length": str(len(chunk)),
                },
            )
            try:
                request.urlopen(patch_req, timeout=_HTTP_TIMEOUT_SEC)
            except error.HTTPError as exc:
                body = _http_error_body(exc)
                if body:
                    print(
                        f"TUS PATCH HTTP {exc.code} at offset {offset}: {body}",
                        file=sys.stderr,
                    )
                if _response_indicates_payload_too_large(exc.code, body):
                    _print_413_guidance(file_path, total)
                raise
            offset += len(chunk)
    if offset != total:
        raise RuntimeError(f"TUS upload incomplete: {offset} of {total} bytes")


def _object_path_for_pdf(rel_posix: str, *, use_source_relative_paths: bool) -> str:
    if use_source_relative_paths:
        return posixpath.join(STORAGE_PREFIX, rel_posix.replace("\\", "/"))
    digest = hashlib.sha256(rel_posix.encode("utf-8")).hexdigest()[:32]
    return f"{STORAGE_PREFIX}/{digest}.pdf"


def _storage_delete_means_missing(http_code: int, body: str) -> bool:
    """Supabase often returns HTTP 400/404 with JSON { error: not_found } for missing objects."""
    if http_code == 404:
        return True
    try:
        payload = json.loads(body)
        if payload.get("error") == "not_found":
            return True
        if str(payload.get("statusCode")) == "404":
            return True
    except Exception:
        pass
    return False


def _delete_storage_object_best_effort(remote_path: str) -> None:
    """Remove an existing object so TUS/simple uploads can replace it (avoids 409)."""
    encoded = _encoded_object_path_for_url(remote_path)
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET_NAME}/{encoded}"
    req = request.Request(
        url,
        method="DELETE",
        headers={
            "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
            "apikey": SERVICE_ROLE_KEY,
        },
    )
    try:
        request.urlopen(req, timeout=_HTTP_TIMEOUT_SEC)
    except error.HTTPError as exc:
        body = _http_error_body(exc)
        if _storage_delete_means_missing(exc.code, body):
            return
        if body:
            print(f"Storage DELETE HTTP {exc.code}: {body}", file=sys.stderr)
        raise


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
    _delete_storage_object_best_effort(remote_path)
    size = file_path.stat().st_size
    if size > _SIMPLE_UPLOAD_MAX_BYTES:
        upload_file_resumable(file_path, remote_path)
        return

    content_type = (
        mimetypes.guess_type(file_path.name)[0] or "application/pdf"
    )
    upload_url = _storage_upload_url(remote_path)
    req = request.Request(
        upload_url,
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
        request.urlopen(req, timeout=_HTTP_TIMEOUT_SEC)
    except error.HTTPError as exc:
        body = _http_error_body(exc)
        if body:
            print(f"Storage API HTTP {exc.code}: {body}", file=sys.stderr)
        if _response_indicates_payload_too_large(exc.code, body):
            print("Retrying with TUS resumable upload...", file=sys.stderr)
            upload_file_resumable(file_path, remote_path)
            return
        if exc.code == 409:
            req = request.Request(
                upload_url,
                data=file_path.read_bytes(),
                method="PUT",
                headers={
                    "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
                    "apikey": SERVICE_ROLE_KEY,
                    "x-upsert": "true",
                    "Content-Type": content_type,
                },
            )
            try:
                request.urlopen(req, timeout=_HTTP_TIMEOUT_SEC)
            except error.HTTPError as put_exc:
                put_body = _http_error_body(put_exc)
                if put_body:
                    print(
                        f"Storage API HTTP {put_exc.code} (PUT): {put_body}",
                        file=sys.stderr,
                    )
                if _response_indicates_payload_too_large(put_exc.code, put_body):
                    _print_413_guidance(file_path, size)
                raise
        else:
            if _response_indicates_payload_too_large(exc.code, body):
                _print_413_guidance(file_path, size)
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
    parser.add_argument(
        "--use-source-relative-paths",
        action="store_true",
        help="Store objects as reference_pdfs/<same path as on disk>. "
        "Often fails on names with commas/parentheses; default is content-hash filenames.",
    )
    parser.add_argument(
        "--max-file-mib",
        type=float,
        default=None,
        metavar="N",
        help="Skip uploads larger than N mebibytes (N × 1024 × 1024). "
        "Oversized paths are recorded under skippedUploads in the manifest; "
        "they will have no PDF URL until you upgrade Storage or host them elsewhere.",
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

    over_free = [
        p
        for p in pdfs
        if p.stat().st_size > _SUPABASE_FREE_PLAN_MAX_FILE_BYTES
    ]
    if over_free:
        print(
            f"Warning: {len(over_free)} PDF(s) are larger than the hosted "
            f"Free-plan Storage cap ({_human_bytes(_SUPABASE_FREE_PLAN_MAX_FILE_BYTES)} per file). "
            "Those uploads will fail with 413 unless you upgrade or use --max-file-mib to skip them.",
            file=sys.stderr,
        )

    max_bytes = (
        int(args.max_file_mib * 1024 * 1024) if args.max_file_mib is not None else None
    )

    files_map: dict[str, str] = {}
    skipped_uploads: dict[str, str] = {}
    for i, pdf in enumerate(pdfs, start=1):
        rel = safe_relative_pdf(root, pdf)
        sz = pdf.stat().st_size
        if max_bytes is not None and sz > max_bytes:
            reason = f"larger than --max-file-mib {args.max_file_mib}"
            print(
                f"[{i}/{len(pdfs)}] SKIP {rel} ({_human_bytes(sz)}): {reason}",
                file=sys.stderr,
            )
            skipped_uploads[rel] = reason
            continue
        remote_object = _object_path_for_pdf(
            rel,
            use_source_relative_paths=args.use_source_relative_paths,
        )
        print(
            f"[{i}/{len(pdfs)}] {rel} ({_human_bytes(sz)}) -> {remote_object}",
        )
        upload_file(pdf, remote_object)
        files_map[rel] = public_object_url(remote_object)

    manifest: dict[str, object] = {
        "version": 1,
        "bucket": BUCKET_NAME,
        "storagePrefix": STORAGE_PREFIX,
        "fileCount": len(files_map),
        "files": files_map,
    }
    if skipped_uploads:
        manifest["skippedUploads"] = skipped_uploads
    args.manifest_out.parent.mkdir(parents=True, exist_ok=True)
    args.manifest_out.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Wrote manifest ({len(files_map)} files) to {args.manifest_out}")
    print(f"Source folder (local only; pass this path to build_reference_book_index.py): {root}")
    print(
        "Next: python tool/build_reference_book_index.py "
        f'"{root}" --all-pdfs --pdf-manifest "{args.manifest_out}"'
    )
    print(
        "Then commit api/reference_books_index.json and deploy "
        "(so pdfUrls point at these storage objects).",
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        raise
