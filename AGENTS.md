# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

Core Review is a Flutter web application for radiology board-review study. Tech stack: Flutter/Dart frontend, Vercel serverless API functions (Node.js), Supabase (auth/storage), OpenAI API (study assistant).

### Flutter SDK

This project requires **Dart SDK ^3.11.1** (Flutter 3.41.5+). In Cursor Cloud, the Flutter SDK is at `/opt/flutter` on `PATH` via `~/.bashrc`. On Windows, a typical install is **`%USERPROFILE%\flutter`** with **`%USERPROFILE%\flutter\bin`** on the user `PATH`.

### Key commands

| Task | Command |
|------|---------|
| Install deps | `flutter pub get` |
| Lint / analyze | `flutter analyze` |
| Run tests | `flutter test` |
| Run dev server | `flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0` |

### Textbook extraction pipeline (data safety)

After changing `tool/extract_pdf_to_json.py` or re-running `tool/reextract_all_books.py`, run the content gate before committing:

| Step | Command |
|------|---------|
| Validate + golden + manifest | `python tool/run_content_pipeline.py` |
| Validation only (writes `assets/data/validation_report.json`) | `python tool/validate_content.py` |
| Fail CI if issues exceed a budget | `python tool/validate_content.py --max-issues 200` |
| Strict (zero tolerance) | `python tool/validate_content.py --fail-on-issues` |
| Regenerate golden snapshot from current JSON | `python tool/write_golden_baseline.py` |
| Restore answers from a backup JSON after extract | `python tool/hybrid_fallback_answers.py --current ... --fallback ...` |
| After re-extract, normalize choices/explanations for validation | `python tool/apply_content_validation_fixes.py` |
| Recover letters from explanation text (safe heuristics) | `python tool/recover_relaxed_answers.py` |

Re-extract merges each book with **safe merge** by default (preserves prior choices/answers when the new run is weaker). Raw extractor output: `python tool/reextract_all_books.py --no-safe-merge`. See `tool/safe_merge_questions.py`. Run **`apply_content_validation_fixes.py`** after a bulk extract so `validate_content.py` can pass (placeholders + `validationRelaxed` for unbound keys).

### Caveats

- `flutter test` should pass all tests; `flutter analyze` should report no issues for this repo state.
- Supabase auth/storage is configured against a remote hosted instance (credentials baked into `lib/config/app_config.dart`). No local Supabase setup is needed.
- The AI study assistant requires an `OPENAI_API_KEY` environment variable set on the Vercel serverless functions (`api/assistant.js`). It is not needed for the core quiz/study functionality.
- When running `flutter run -d web-server`, the app serves on the specified port. Use Chrome to access it. The `web-server` device does not support hot-reload triggered by keypress; use `flutter run -d chrome` locally if interactive hot-reload is desired (requires a display).
