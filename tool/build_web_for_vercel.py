from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
BUILD_ROOT = PROJECT_ROOT / "build"
OUTPUT_DIR = BUILD_ROOT / "web_vercel"


def optional_env(name: str) -> str:
    return os.environ.get(name, "").strip()


def copy_project() -> Path:
    temp_project = Path(tempfile.mkdtemp(prefix="core_review_web_"))
    shutil.copytree(
        PROJECT_ROOT,
        temp_project,
        ignore=shutil.ignore_patterns(
            "build",
            ".dart_tool",
            ".idea",
            "windows",
            "android",
            "test",
            "assets/book_images",
        ),
        dirs_exist_ok=True,
    )
    return temp_project


def copy_book_images(output_dir: Path) -> None:
    """Copy book_images to output so they are served at /book_images/."""
    source = PROJECT_ROOT / "assets" / "book_images"
    if not source.exists():
        return
    dest = output_dir / "book_images"
    if dest.exists():
        shutil.rmtree(dest, ignore_errors=True)
    shutil.copytree(source, dest, dirs_exist_ok=True)


def trim_pubspec_assets(temp_project: Path) -> None:
    pubspec_path = temp_project / "pubspec.yaml"
    pubspec = pubspec_path.read_text(encoding="utf-8")
    pubspec = pubspec.replace("    - assets/book_images/\n", "")
    pubspec_path.write_text(pubspec, encoding="utf-8", newline="\n")


def copy_vercel_api(output_dir: Path) -> None:
    source_api_dir = PROJECT_ROOT / "api"
    if not source_api_dir.exists():
        return

    shutil.copytree(source_api_dir, output_dir / "api", dirs_exist_ok=True)


def run(command: list[str], *, cwd: Path) -> None:
    subprocess.run(command, cwd=str(cwd), check=True)


def main() -> None:
    supabase_url = optional_env("SUPABASE_URL")
    supabase_anon_key = optional_env("SUPABASE_ANON_KEY")
    content_base_url = optional_env("CONTENT_BASE_URL")
    if not content_base_url and os.environ.get("VERCEL_URL"):
        content_base_url = f"https://{os.environ['VERCEL_URL']}"
    flutter_exe = os.environ.get("FLUTTER_EXE", "flutter")

    if not content_base_url:
        raise RuntimeError(
            "CONTENT_BASE_URL must be set for the web build, or run on Vercel."
        )

    temp_project = copy_project()
    trim_pubspec_assets(temp_project)

    run([flutter_exe, "pub", "get"], cwd=temp_project)
    run([flutter_exe, "create", ".", "--platforms=web"], cwd=temp_project)
    run(
        [
            flutter_exe,
            "build",
            "web",
            "--release",
            f"--dart-define=SUPABASE_URL={supabase_url}",
            f"--dart-define=SUPABASE_ANON_KEY={supabase_anon_key}",
            f"--dart-define=CONTENT_BASE_URL={content_base_url}",
        ],
        cwd=temp_project,
    )

    built_web_dir = temp_project / "build" / "web"
    if OUTPUT_DIR.exists():
        shutil.rmtree(OUTPUT_DIR, ignore_errors=True)
    shutil.copytree(built_web_dir, OUTPUT_DIR, dirs_exist_ok=True)
    shutil.copy2(PROJECT_ROOT / "vercel.json", OUTPUT_DIR / "vercel.json")
    copy_vercel_api(OUTPUT_DIR)
    copy_book_images(OUTPUT_DIR)
    shutil.rmtree(temp_project, ignore_errors=True)

    print(f"Web build ready at {OUTPUT_DIR}")
    print(
        "Set CONTENT_BASE_URL to your deployment URL (e.g. https://your-project.vercel.app)"
        " so images load from /book_images/"
    )


if __name__ == "__main__":
    main()
