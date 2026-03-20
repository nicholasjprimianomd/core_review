import '../../models/book_models.dart';

enum ExamMode {
  test,
  tutor,
}

enum CompletionFilter {
  allPool,
  unansweredOnly,
  incorrectOnly,
  answeredOnly,
}

class ExamScopeSelection {
  const ExamScopeSelection({
    required this.bookIds,
    required this.chapterIds,
    required this.sectionIds,
  });

  final Set<String> bookIds;
  final Set<String> chapterIds;
  final Set<String> sectionIds;

  bool get isEmpty =>
      bookIds.isEmpty && chapterIds.isEmpty && sectionIds.isEmpty;
}

class ExamSessionOptions {
  const ExamSessionOptions({
    required this.mode,
    required this.title,
    this.timeLimit,
  });

  final ExamMode mode;
  final String title;
  final Duration? timeLimit;

  bool get deferRevealUntilEnd => mode == ExamMode.test;
}

class ExamLaunchRequest {
  const ExamLaunchRequest({
    required this.title,
    required this.questions,
    required this.options,
  });

  final String title;
  final List<BookQuestion> questions;
  final ExamSessionOptions options;
}
