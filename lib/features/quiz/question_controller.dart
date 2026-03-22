import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import '../progress/progress_repository.dart';

class QuestionController extends ChangeNotifier {
  QuestionController({
    required List<BookQuestion> questions,
    required ProgressRepository progressRepository,
    required StudyProgress initialProgress,
    required int initialIndex,
    this.onProgressChanged,
    this.deferRevealUntilExamEnd = false,
  }) : _questions = List<BookQuestion>.unmodifiable(questions),
       _progressRepository = progressRepository,
       _progress = initialProgress,
       _currentIndex = initialIndex.clamp(0, questions.length - 1) {
    _syncLastVisitedQuestion();
  }

  final List<BookQuestion> _questions;
  final ProgressRepository _progressRepository;
  final ValueChanged<StudyProgress>? onProgressChanged;

  /// When true (test block), submissions do not set [QuestionProgress.revealedAt] until
  /// [finishDeferredExamReveals] runs.
  final bool deferRevealUntilExamEnd;

  StudyProgress _progress;
  int _currentIndex;
  String? _draftChoice;
  bool _isSaving = false;
  bool _deferredRevealsCompleted = false;

  List<BookQuestion> get questions => _questions;

  StudyProgress get progress => _progress;

  BookQuestion get currentQuestion => _questions[_currentIndex];

  QuestionProgress? get currentQuestionProgress =>
      _progress.answers[currentQuestion.id];

  bool get hasRevealedCurrentAnswer =>
      currentQuestionProgress?.isRevealed ?? false;

  bool get deferredRevealsCompleted => _deferredRevealsCompleted;

  bool get explanationsVisibleForCurrent =>
      _deferredRevealsCompleted || hasRevealedCurrentAnswer;

  int get currentIndex => _currentIndex;

  int get questionCount => _questions.length;

  double get completionFraction =>
      questionCount == 0 ? 0 : (_currentIndex + 1) / questionCount;

  String? get selectedChoice =>
      currentQuestionProgress?.selectedChoice ?? _draftChoice;

  bool get hasSubmittedCurrentAnswer => currentQuestionProgress != null;

  bool get canSubmit =>
      !hasSubmittedCurrentAnswer &&
      !_isSaving &&
      (_draftChoice?.isNotEmpty ?? false);

  bool get isCurrentQuestionMultipart =>
      _multipartGroupFor(currentQuestion).length > 1;

  bool get isCurrentQuestionLastPart {
    final group = _multipartGroupFor(currentQuestion);
    return group.isEmpty || group.last.id == currentQuestion.id;
  }

  bool get shouldUseNextPartAction =>
      isCurrentQuestionMultipart && !isCurrentQuestionLastPart;

  bool get canAdvanceToNextPart =>
      !_isSaving &&
      _nextMultipartPartIndexFor(currentQuestion) != null &&
      (hasSubmittedCurrentAnswer || (_draftChoice?.isNotEmpty ?? false));

  bool get canGoPrevious => _currentIndex > 0;

  bool get canGoNext => _currentIndex < _questions.length - 1;

  bool get isSaving => _isSaving;

  void selectChoice(String choice) {
    if (hasSubmittedCurrentAnswer) {
      return;
    }
    _draftChoice = choice;
    notifyListeners();
  }

  Future<void> submitCurrentAnswer() async {
    if (!canSubmit) {
      return;
    }

    await _saveCurrentAnswer(revealAnswer: !deferRevealUntilExamEnd);
  }

  Future<void> submitCurrentPartAndAdvance() async {
    final nextIndex = _nextMultipartPartIndexFor(currentQuestion);
    if (nextIndex == null || _isSaving) {
      return;
    }

    if (hasSubmittedCurrentAnswer) {
      _currentIndex = nextIndex;
      _draftChoice = null;
      _syncLastVisitedQuestion();
      notifyListeners();
      return;
    }

    if (!canSubmit) {
      return;
    }

    await _saveCurrentAnswer(
      revealAnswer: false,
      nextIndexAfterSave: nextIndex,
    );
  }

  Future<void> finishDeferredExamReveals() async {
    if (!deferRevealUntilExamEnd || _deferredRevealsCompleted) {
      return;
    }

    final now = DateTime.now();
    final updatedAnswers = Map<String, QuestionProgress>.from(_progress.answers);
    for (final question in _questions) {
      final existing = updatedAnswers[question.id];
      if (existing == null || existing.isRevealed) {
        continue;
      }
      updatedAnswers[question.id] = existing.copyWith(revealedAt: now);
    }

    _progress = _progress.copyWith(answers: updatedAnswers, touch: true);
    _deferredRevealsCompleted = true;
    _publishProgress();
    _isSaving = true;
    notifyListeners();

    await _progressRepository.saveProgress(_progress);

    _isSaving = false;
    notifyListeners();
  }

  void goToPrevious() {
    if (!canGoPrevious) {
      return;
    }
    _currentIndex -= 1;
    _draftChoice = null;
    _syncLastVisitedQuestion();
    notifyListeners();
  }

  void goToNext() {
    if (!canGoNext) {
      return;
    }
    _currentIndex += 1;
    _draftChoice = null;
    _syncLastVisitedQuestion();
    notifyListeners();
  }

  void jumpToIndex(int index) {
    if (index < 0 || index >= _questions.length || index == _currentIndex) {
      return;
    }
    _currentIndex = index;
    _draftChoice = null;
    _syncLastVisitedQuestion();
    notifyListeners();
  }

  void _syncLastVisitedQuestion() {
    _progress = _progress.copyWith(
      lastVisitedQuestionId: currentQuestion.id,
    );
    _publishProgress();
    unawaited(_progressRepository.saveProgress(_progress, syncToCloud: false));
  }

  void _publishProgress() {
    onProgressChanged?.call(_progress);
  }

  Future<void> _saveCurrentAnswer({
    required bool revealAnswer,
    int? nextIndexAfterSave,
  }) async {
    final question = currentQuestion;
    final choice = _draftChoice!;
    final answeredAt = DateTime.now();
    final revealedAt = revealAnswer ? answeredAt : null;
    final updatedAnswers = Map<String, QuestionProgress>.from(_progress.answers)
      ..[question.id] = QuestionProgress(
        selectedChoice: choice,
        isCorrect: choice == question.correctChoice,
        answeredAt: answeredAt,
        revealedAt: revealedAt,
      );

    if (revealAnswer) {
      _markStemGroupAsRevealed(
        question: question,
        answers: updatedAnswers,
        revealedAt: answeredAt,
      );
    }

    _progress = _progress.copyWith(
      answers: updatedAnswers,
      lastVisitedQuestionId: question.id,
      touch: true,
    );
    _publishProgress();
    _isSaving = true;
    notifyListeners();

    await _progressRepository.saveProgress(_progress);

    _isSaving = false;
    if (nextIndexAfterSave != null) {
      _currentIndex = nextIndexAfterSave;
      _draftChoice = null;
      _syncLastVisitedQuestion();
    }
    notifyListeners();
  }

  void _markStemGroupAsRevealed({
    required BookQuestion question,
    required Map<String, QuestionProgress> answers,
    required DateTime revealedAt,
  }) {
    for (final groupQuestion in _multipartGroupFor(question)) {
      final existing = answers[groupQuestion.id];
      if (existing == null || existing.isRevealed) {
        continue;
      }
      answers[groupQuestion.id] = existing.copyWith(revealedAt: revealedAt);
    }
  }

  List<BookQuestion> _multipartGroupFor(BookQuestion question) {
    final groupKey = _multipartGroupKey(question);
    return _questions
        .where((candidate) => _multipartGroupKey(candidate) == groupKey)
        .toList(growable: false)
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
  }

  int? _nextMultipartPartIndexFor(BookQuestion question) {
    final group = _multipartGroupFor(question);
    final groupPosition = group.indexWhere((entry) => entry.id == question.id);
    if (groupPosition < 0 || groupPosition >= group.length - 1) {
      return null;
    }

    final nextQuestionId = group[groupPosition + 1].id;
    final nextIndex = _questions.indexWhere(
      (candidate) => candidate.id == nextQuestionId,
    );
    return nextIndex >= 0 ? nextIndex : null;
  }

  String _multipartGroupKey(BookQuestion question) {
    return [
      question.bookId,
      question.chapterId,
      question.sectionId ?? '',
      question.stemGroup,
    ].join('::');
  }
}
