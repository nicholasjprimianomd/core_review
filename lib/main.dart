import 'dart:async';

import 'package:flutter/material.dart';

import 'features/analytics/analytics_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/books/book_library_screen.dart';
import 'features/chapters/chapter_list_screen.dart';
import 'features/progress/progress_repository.dart';
import 'features/exam/custom_exam_setup_screen.dart';
import 'features/exam/exam_history_models.dart';
import 'features/exam/exam_history_repository.dart';
import 'features/exam/exam_history_screen.dart';
import 'features/exam/exam_session_models.dart';
import 'features/progress/progress_screen.dart';
import 'features/quiz/question_screen.dart';
import 'features/search/search_screen.dart';
import 'models/book_models.dart';
import 'models/progress_models.dart';
import 'models/study_data_models.dart';
import 'repositories/app_settings_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/book_repository.dart';
import 'repositories/cloud_progress_repository.dart';
import 'repositories/study_data_repository.dart';

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
      _appSettingsRepository = AppSettingsRepository(),
      _studyDataRepository = StudyDataRepository(),
      _examHistoryRepository = ExamHistoryRepository();

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final ValueNotifier<StudyProgress> _progressNotifier = ValueNotifier(
    StudyProgress.empty,
  );
  final ValueNotifier<StudyData> _studyDataNotifier = ValueNotifier(
    StudyData.empty,
  );
  late final AuthRepository _authRepository;
  late final ProgressRepository _progressRepository = ProgressRepository(
    cloudProgressRepository: _authRepository.client == null
        ? null
        : CloudProgressRepository(_authRepository.client!),
    // Use AuthRepository as source of truth so userId is available as soon as
    // loadSession() completes, even before setState assigns _currentUser.
    userIdProvider: () => _authRepository.currentUser?.id,
  );
  late final BookRepository _bookRepository;
  late final AppSettingsRepository _appSettingsRepository;
  late final StudyDataRepository _studyDataRepository;
  late final ExamHistoryRepository _examHistoryRepository;

  late final Future<void> _bootstrapFuture = _bootstrap();

  BookContent? _content;
  ThemeMode _themeMode = ThemeMode.dark;
  double _textScale = AppSettingsRepository.defaultTextScale;
  AuthUser? _currentUser;

  Future<void> _bootstrap() async {
    final themeMode = await _appSettingsRepository.loadThemeMode();
    final textScale = await _appSettingsRepository.loadTextScale();
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
    // ProgressRepository.userIdProvider reads _currentUser; set it before load
    // so logged-in users merge cloud + per-user localStorage, not guest only.
    _currentUser = currentUser;
    StudyProgress progress;
    try {
      progress = await _progressRepository.loadProgress();
    } catch (_) {
      progress = StudyProgress.empty;
    }

    StudyData studyData;
    try {
      studyData = await _studyDataRepository.load();
    } catch (_) {
      studyData = StudyData.empty;
    }

    _setProgress(progress);
    _studyDataNotifier.value = studyData;
    if (!mounted) {
      return;
    }
    setState(() {
      _themeMode = themeMode;
      _textScale = textScale;
      _content = content;
      _currentUser = currentUser;
    });
  }

  @override
  void dispose() {
    unawaited(_authRepository.dispose());
    _progressNotifier.dispose();
    _studyDataNotifier.dispose();
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

  Future<void> _setTextScale(double value) async {
    final clamped = value.clamp(
      AppSettingsRepository.minTextScale,
      AppSettingsRepository.maxTextScale,
    );
    await _appSettingsRepository.saveTextScale(clamped);
    if (!mounted) {
      return;
    }
    setState(() {
      _textScale = clamped;
    });
  }

  Future<void> _openFontSettings() async {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    final scaleBeforeDialog = _textScale;
    var draft = _textScale;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Text size'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Slider(
                    value: draft,
                    min: AppSettingsRepository.minTextScale,
                    max: AppSettingsRepository.maxTextScale,
                    divisions: 13,
                    label: '${(draft * 100).round()}%',
                    onChanged: (v) {
                      setLocalState(() => draft = v);
                      unawaited(_setTextScale(v));
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Smaller',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'Larger',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed == true) {
      return;
    }
    await _setTextScale(scaleBeforeDialog);
  }

  Future<void> _recordExamCompletion(ExamCompletionSnapshot snapshot) async {
    final entry = ExamHistoryEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: snapshot.title,
      questionIds: snapshot.questionIds,
      examMode: snapshot.examMode,
      startedAt: snapshot.startedAt,
      endedAt: snapshot.endedAt,
      timeLimitSeconds: snapshot.timeLimit?.inSeconds,
    );
    await _examHistoryRepository.prependEntry(entry);
  }

  Future<void> _startExamReviewFromHistory(ExamHistoryEntry entry) async {
    final content = _content;
    if (content == null) {
      return;
    }
    List<BookQuestion> questions;
    try {
      questions = content.questionsForIdsInOrder(entry.questionIds);
    } catch (_) {
      final messenger = _navigatorKey.currentContext != null
          ? ScaffoldMessenger.maybeOf(_navigatorKey.currentContext!)
          : null;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Some questions are no longer available; review may be incomplete.',
          ),
        ),
      );
      questions = <BookQuestion>[];
      for (final id in entry.questionIds) {
        try {
          questions.add(content.questionById(id));
        } catch (_) {
          // Skip removed questions.
        }
      }
      if (questions.isEmpty) {
        return;
      }
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (context) {
          return QuestionScreen(
            title: '${entry.title} (review)',
            content: content,
            questions: questions,
            progressRepository: _progressRepository,
            initialProgress: _progressNotifier.value,
            initialStudyData: _studyDataNotifier.value,
            initialIndex: 0,
            themeMode: _themeMode,
            onToggleTheme: _toggleThemeMode,
            onProgressChanged: _setProgress,
            onStudyDataChanged: _setStudyData,
            readOnlyAfterExam: true,
            onEndReview: () => Navigator.of(context).pop(),
            onOpenFontSettings: _openFontSettings,
          );
        },
      ),
    );

    await _refreshProgress();
  }

  Future<void> _openExamHistory() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (context) {
          return ExamHistoryScreen(
            loadEntries: () => _examHistoryRepository.loadEntries(),
            onOpenEntry: (entry) {
              Navigator.of(context).pop();
              unawaited(_startExamReviewFromHistory(entry));
            },
            themeMode: _themeMode,
            onToggleTheme: _toggleThemeMode,
          );
        },
      ),
    );
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

  Future<void> _openCustomExamSetup() async {
    final navigator = _navigatorKey.currentState;
    final content = _content;
    if (navigator == null || content == null) {
      return;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (context) {
          return CustomExamSetupScreen(
            content: content,
            progressListenable: _progressNotifier,
            themeMode: _themeMode,
            onToggleTheme: _toggleThemeMode,
            onLaunch: (request) {
              Navigator.of(context).pop();
              unawaited(_startExam(request));
            },
          );
        },
      ),
    );

    await _refreshProgress();
  }

  Future<void> _startExam(ExamLaunchRequest request) async {
    if (request.questions.isEmpty) {
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (context) {
          return QuestionScreen(
            title: request.title,
            content: _content!,
            questions: request.questions,
            progressRepository: _progressRepository,
            initialProgress: _progressNotifier.value,
            initialStudyData: _studyDataNotifier.value,
            initialIndex: 0,
            themeMode: _themeMode,
            onToggleTheme: _toggleThemeMode,
            onProgressChanged: _setProgress,
            onStudyDataChanged: _setStudyData,
            examSession: request.options,
            onExamCompleted: _recordExamCompletion,
            onOpenFontSettings: _openFontSettings,
          );
        },
      ),
    );

    await _refreshProgress();
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
            initialStudyData: _studyDataNotifier.value,
            initialIndex: initialIndex,
            themeMode: _themeMode,
            onToggleTheme: _toggleThemeMode,
            onProgressChanged: _setProgress,
            onStudyDataChanged: _setStudyData,
            onOpenFontSettings: _openFontSettings,
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

  void _setStudyData(StudyData data) {
    _studyDataNotifier.value = data;
    unawaited(_studyDataRepository.save(data));
  }

  Future<void> _openAnalytics() async {
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
          return AnalyticsScreen(
            content: content,
            progressListenable: _progressNotifier,
            themeMode: _themeMode,
            onToggleTheme: _toggleThemeMode,
          );
        },
      ),
    );
  }

  Future<void> _openSearch() async {
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
          return SearchScreen(
            content: content,
            progressListenable: _progressNotifier,
            studyDataListenable: _studyDataNotifier,
            themeMode: _themeMode,
            onToggleTheme: _toggleThemeMode,
            onStartStudySet: _startStudySet,
          );
        },
      ),
    );

    await _refreshProgress();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Core Review',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(_textScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ).copyWith(
          surface: Colors.black,
          surfaceDim: const Color(0xFF000000),
          surfaceBright: const Color(0xFF1A1A1A),
          surfaceContainerLowest: const Color(0xFF050505),
          surfaceContainerLow: const Color(0xFF0F0F0F),
          surfaceContainer: const Color(0xFF161616),
          surfaceContainerHigh: const Color(0xFF1E1E1E),
          surfaceContainerHighest: const Color(0xFF262626),
        ),
      ),
      themeMode: _themeMode,
      home: _content != null
          ? BookLibraryScreen(
              content: _content!,
              progressListenable: _progressNotifier,
              studyDataListenable: _studyDataNotifier,
              themeMode: _themeMode,
              currentUserEmail: _currentUser?.email,
              onToggleTheme: _toggleThemeMode,
              onOpenAuth: _openAuth,
              onOpenProgress: _openProgress,
              onOpenAnalytics: _openAnalytics,
              onOpenSearch: _openSearch,
              onOpenBook: _openBook,
              onStartStudySet: _startStudySet,
              onOpenCustomExam: _openCustomExamSetup,
              onOpenExamHistory: _openExamHistory,
              onOpenFontSettings: _openFontSettings,
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
                  studyDataListenable: _studyDataNotifier,
                  themeMode: _themeMode,
                  currentUserEmail: _currentUser?.email,
                  onToggleTheme: _toggleThemeMode,
                  onOpenAuth: _openAuth,
                  onOpenProgress: _openProgress,
                  onOpenAnalytics: _openAnalytics,
                  onOpenSearch: _openSearch,
                  onOpenBook: _openBook,
                  onStartStudySet: _startStudySet,
                  onOpenCustomExam: _openCustomExamSetup,
                  onOpenExamHistory: _openExamHistory,
                  onOpenFontSettings: _openFontSettings,
                );
              },
            ),
    );
  }
}
