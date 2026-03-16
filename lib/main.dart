import 'dart:async';

import 'package:flutter/material.dart';

import 'features/auth/auth_screen.dart';
import 'features/books/book_library_screen.dart';
import 'features/chapters/chapter_list_screen.dart';
import 'features/progress/progress_repository.dart';
import 'features/progress/progress_screen.dart';
import 'features/quiz/question_screen.dart';
import 'models/book_models.dart';
import 'models/progress_models.dart';
import 'repositories/app_settings_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/book_repository.dart';
import 'repositories/cloud_progress_repository.dart';

void main() {
  runApp(const CoreReviewApp());
}

class CoreReviewApp extends StatefulWidget {
  const CoreReviewApp({super.key});

  @override
  State<CoreReviewApp> createState() => _CoreReviewAppState();
}

class _CoreReviewAppState extends State<CoreReviewApp> {
  _CoreReviewAppState()
    : _authRepository = AuthRepository(),
      _bookRepository = BookRepository(),
      _appSettingsRepository = AppSettingsRepository();

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final ValueNotifier<StudyProgress> _progressNotifier = ValueNotifier(
    StudyProgress.empty,
  );
  late final AuthRepository _authRepository;
  late final ProgressRepository _progressRepository = ProgressRepository(
    cloudProgressRepository: _authRepository.client == null
        ? null
        : CloudProgressRepository(_authRepository.client!),
    userIdProvider: () => _currentUser?.id,
  );
  late final BookRepository _bookRepository;
  late final AppSettingsRepository _appSettingsRepository;

  late final Future<void> _bootstrapFuture = _bootstrap();

  BookContent? _content;
  ThemeMode _themeMode = ThemeMode.dark;
  AuthUser? _currentUser;

  Future<void> _bootstrap() async {
    final themeMode = await _appSettingsRepository.loadThemeMode();
    final content = await _bookRepository.loadContent();
    AuthUser? currentUser;
    try {
      currentUser = await _authRepository.recoverSessionFromCurrentUrlIfPresent();
    } catch (_) {
      currentUser = null;
    }
    try {
      currentUser ??= await _authRepository.loadSession();
    } catch (_) {
      currentUser = null;
    }
    _currentUser = currentUser;
    StudyProgress progress;
    try {
      progress = await _progressRepository.loadProgress();
    } catch (_) {
      progress = StudyProgress.empty;
    }

    _themeMode = themeMode;
    _content = content;
    _setProgress(progress);
  }

  @override
  void dispose() {
    unawaited(_authRepository.dispose());
    _progressNotifier.dispose();
    super.dispose();
  }

  Future<void> _refreshAuthAndProgress() async {
    AuthUser? updatedUser;
    try {
      updatedUser = await _authRepository.loadSession();
    } catch (_) {
      updatedUser = null;
    }
    _currentUser = updatedUser;
    StudyProgress updatedProgress;
    try {
      updatedProgress = await _progressRepository.loadProgress();
    } catch (_) {
      updatedProgress = StudyProgress.empty;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _currentUser = updatedUser;
    });
    _setProgress(updatedProgress);
  }

  Future<void> _refreshProgress() async {
    StudyProgress updated;
    try {
      updated = await _progressRepository.loadProgress();
    } catch (_) {
      updated = StudyProgress.empty;
    }
    if (!mounted) {
      return;
    }
    _setProgress(updated);
  }

  Future<void> _toggleThemeMode() async {
    final nextThemeMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    await _appSettingsRepository.saveThemeMode(nextThemeMode);
    if (!mounted) {
      return;
    }
    setState(() {
      _themeMode = nextThemeMode;
    });
  }

  Future<void> _openAuth() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    final changed = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) {
          return AuthScreen(
            authRepository: _authRepository,
            currentUser: _currentUser,
          );
        },
      ),
    );

    if (changed == true) {
      await _refreshAuthAndProgress();
    }
  }

  Future<void> _startStudySet(
    String title,
    List<BookQuestion> questions,
  ) async {
    if (questions.isEmpty) {
      return;
    }

    final initialIndex = _resolveInitialIndex(questions);

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) {
          return QuestionScreen(
            title: title,
            content: _content!,
            questions: questions,
            progressRepository: _progressRepository,
            initialProgress: _progressNotifier.value,
            initialIndex: initialIndex,
            themeMode: _themeMode,
            onToggleTheme: _toggleThemeMode,
            onProgressChanged: _setProgress,
          );
        },
      ),
    );

    await _refreshProgress();
  }

  Future<void> _openBook(ReviewBook book) async {
    final content = _content;
    if (content == null) {
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) {
          return ChapterListScreen(
            book: book,
            content: content,
            progressListenable: _progressNotifier,
            themeMode: _themeMode,
            onToggleTheme: _toggleThemeMode,
            onOpenProgress: _openProgress,
            onStartStudySet: _startStudySet,
          );
        },
      ),
    );

    await _refreshProgress();
  }

  Future<void> _openProgress() async {
    final content = _content;
    if (content == null) {
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) {
          return ProgressScreen(
            content: content,
            progressListenable: _progressNotifier,
            themeMode: _themeMode,
            onToggleTheme: _toggleThemeMode,
            onOpenBook: _openBook,
            onStartStudySet: _startStudySet,
            onResetProgress: _resetProgress,
          );
        },
      ),
    );

    await _refreshProgress();
  }

  Future<void> _resetProgress() async {
    await _progressRepository.resetProgress();
    await _refreshProgress();
  }

  int _resolveInitialIndex(List<BookQuestion> questions) {
    final progress = _progressNotifier.value;
    final lastVisitedQuestionId = progress.lastVisitedQuestionId;
    if (lastVisitedQuestionId != null) {
      final matchingIndex = questions.indexWhere(
        (question) => question.id == lastVisitedQuestionId,
      );
      if (matchingIndex >= 0) {
        return matchingIndex;
      }
    }

    final firstUnansweredIndex = questions.indexWhere(
      (question) => !progress.answers.containsKey(question.id),
    );
    return firstUnansweredIndex >= 0 ? firstUnansweredIndex : 0;
  }

  void _setProgress(StudyProgress progress) {
    _progressNotifier.value = progress;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Core Review',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: _content != null
          ? BookLibraryScreen(
              content: _content!,
              progressListenable: _progressNotifier,
              themeMode: _themeMode,
              currentUserEmail: _currentUser?.email,
              onToggleTheme: _toggleThemeMode,
              onOpenAuth: _openAuth,
              onOpenProgress: _openProgress,
              onOpenBook: _openBook,
              onStartStudySet: _startStudySet,
            )
          : FutureBuilder<void>(
              future: _bootstrapFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return Scaffold(
                    body: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Unable to load study content.\n\n${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }

                return BookLibraryScreen(
                  content: _content!,
                  progressListenable: _progressNotifier,
                  themeMode: _themeMode,
                  currentUserEmail: _currentUser?.email,
                  onToggleTheme: _toggleThemeMode,
                  onOpenAuth: _openAuth,
                  onOpenProgress: _openProgress,
                  onOpenBook: _openBook,
                  onStartStudySet: _startStudySet,
                );
              },
            ),
    );
  }
}
