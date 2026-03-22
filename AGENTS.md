# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

Core Review is a Flutter web application for radiology board-review study. Tech stack: Flutter/Dart frontend, Vercel serverless API functions (Node.js), Supabase (auth/storage), OpenAI API (study assistant).

### Flutter SDK

This project requires **Dart SDK ^3.11.1** (Flutter 3.41.5+). The Flutter SDK is installed at `/opt/flutter` and is on `PATH` via `~/.bashrc`.

### Key commands

| Task | Command |
|------|---------|
| Install deps | `flutter pub get` |
| Lint / analyze | `flutter analyze` |
| Run tests | `flutter test` |
| Run dev server | `flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0` |

### Caveats

- The `assets/data/questions/` directory referenced in `pubspec.yaml` does not exist in the repo. This produces a non-fatal warning during analyze, test, and run. It does not block functionality.
- `flutter analyze` shows 3 pre-existing info/warning diagnostics (1 deprecation, 1 missing asset dir, 1 unnecessary import). None are errors.
- 3 of 9 tests fail (`progress_flow_test.dart`, `widget_test.dart`, `exam_pool_builder_test.dart`). These are pre-existing failures in the codebase, not environment issues.
- Supabase auth/storage is configured against a remote hosted instance (credentials baked into `lib/config/app_config.dart`). No local Supabase setup is needed.
- The AI study assistant requires an `OPENAI_API_KEY` environment variable set on the Vercel serverless functions (`api/assistant.js`). It is not needed for the core quiz/study functionality.
- When running `flutter run -d web-server`, the app serves on the specified port. Use Chrome to access it. The `web-server` device does not support hot-reload triggered by keypress; use `flutter run -d chrome` locally if interactive hot-reload is desired (requires a display).
