#!/usr/bin/env python3
"""Gate: validate quiz JSON, check golden baseline, refresh extraction manifest."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run validation + golden checks after content changes.",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument(
        "--skip-golden",
        action="store_true",
        help="Skip tool/check_golden_baseline.py (not recommended before merge).",
    )
    parser.add_argument(
        "--skip-manifest",
        action="store_true",
        help="Skip writing tool/extraction_manifest.json.",
    )
    parser.add_argument(
        "--max-issues",
        type=int,
        default=None,
        metavar="N",
        help="Forward to validate_content: fail if issue count exceeds N.",
    )
    parser.add_argument(
        "--fail-on-issues",
        action="store_true",
        help="Forward to validate_content: fail if any issue is reported.",
    )
    args = parser.parse_args()
    root = args.project_root.expanduser().resolve()
    py = sys.executable
    tool = root / "tool"

    vcmd = [
        py,
        str(tool / "validate_content.py"),
        "--project-root",
        str(root),
    ]
    if args.fail_on_issues:
        vcmd.append("--fail-on-issues")
    if args.max_issues is not None:
        vcmd.extend(["--max-issues", str(args.max_issues)])

    r = subprocess.run(vcmd, cwd=str(root))
    if r.returncode != 0:
        raise SystemExit(r.returncode)

    if not args.skip_golden:
        r = subprocess.run(
            [py, str(tool / "check_golden_baseline.py"), "--project-root", str(root)],
            cwd=str(root),
        )
        if r.returncode != 0:
            raise SystemExit(r.returncode)

    if not args.skip_manifest:
        subprocess.run(
            [py, str(tool / "write_extraction_manifest.py"), "--project-root", str(root)],
            cwd=str(root),
            check=True,
        )

    print("Content pipeline passed.")


if __name__ == "__main__":
    main()
