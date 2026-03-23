#!/usr/bin/env python3
"""Record hashes of extraction tooling for traceability."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    args = parser.parse_args()
    root = args.project_root.expanduser().resolve()
    tool_dir = root / "tool"
    files = [
        tool_dir / "extract_pdf_to_json.py",
        tool_dir / "safe_merge_questions.py",
        tool_dir / "reextract_all_books.py",
        tool_dir / "hybrid_fallback_answers.py",
        tool_dir / "apply_content_validation_fixes.py",
        tool_dir / "recover_relaxed_answers.py",
        tool_dir / "validate_content.py",
        root / "assets" / "data" / "books.json",
    ]
    missing = [str(p.relative_to(root)) for p in files if not p.is_file()]
    if missing:
        raise SystemExit(f"Missing files: {missing}")

    payload = {
        "version": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "files": {
            str(p.relative_to(root)).replace("\\", "/"): {
                "sha256": _sha256(p),
            }
            for p in files
        },
    }
    out = tool_dir / "extraction_manifest.json"
    out.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
