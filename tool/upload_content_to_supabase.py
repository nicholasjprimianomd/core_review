from __future__ import annotations

import mimetypes
import os
import sys
from pathlib import Path
from urllib import error, request


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ASSETS_ROOT = PROJECT_ROOT / "assets"
BUCKET_NAME = os.environ.get("SUPABASE_STORAGE_BUCKET", "core-review-content")
SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")


def require_env() -> None:
    if not SUPABASE_URL or not SERVICE_ROLE_KEY:
        raise RuntimeError(
            "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set before upload."
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
    content_type = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
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


def iter_content_files() -> list[tuple[Path, str]]:
    files: list[tuple[Path, str]] = []
    for folder_name in ("data", "book_images"):
        folder = ASSETS_ROOT / folder_name
        for file_path in folder.rglob("*"):
            if not file_path.is_file():
                continue
            relative_path = file_path.relative_to(ASSETS_ROOT).as_posix()
            files.append((file_path, relative_path))
    return files


def main() -> None:
    require_env()
    create_bucket()

    files = iter_content_files()
    for index, (file_path, remote_path) in enumerate(files, start=1):
      print(f"[{index}/{len(files)}] Uploading {remote_path}")
      upload_file(file_path, remote_path)

    print("Upload complete.")
    print(
        f"Public content base URL: {SUPABASE_URL}/storage/v1/object/public/{BUCKET_NAME}"
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        raise
