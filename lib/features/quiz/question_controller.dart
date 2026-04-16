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
    this.readOnlyAfterExam = false,
  }) : _questions = List<BookQuestion>.unmodifiable(questions),
       _progressRepository = progressRepository,
       _progress = initialProgress,
       _currentIndex = initialIndex.clamp(0, questions.length - 1) {
    if (!readOnlyAfterExam) {
      _syncLastVisitedQuestion();
    }
  }

  final List<BookQuestion> _questions;
  final ProgressRepository _progressRepository;
  final ValueChanged<StudyProgress>? onProgressChanged;

  /// When true (test block), submissions do not set [QuestionProgress.revealedAt] until
  /// [finishDeferredExamReveals] runs.
  final bool deferRevealUntilExamEnd;

  /// Review mode after an exam: navigate questions without changing progress.
  final bool readOnlyAfterExam;

  StudyProgress _progress;
  int _currentIndex;
  String? _draftChoice;
  final Map<String, Map<String, String>> _draftItemSelections =
      <String, Map<String, String>>{};
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

  /// Current per-item selections for the active matching question.
  /// Returns the submitted selections when revealed, otherwise the in-progress
  /// draft (possibly empty). The keys are [MatchingItem.label]s.
  Map<String, String> get currentMatchingSelections {
    final question = currentQuestion;
    if (!question.isMatching) {
      return const <String, String>{};
    }
    final submitted = currentQuestionProgress?.itemSelections;
    if (submitted != null && submitted.isNotEmpty) {
      return Map<String, String>.unmodifiable(submitted);
    }
    return Map<String, String>.unmodifiable(
      _draftItemSelections[question.id] ?? const <String, String>{},
    );
  }

  bool _matchingDraftComplete(BookQuestion question) {
    if (!question.isMatching) {
      return false;
    }
    final draft = _draftItemSelections[question.id];
    if (draft == null || draft.length < question.matchingItems.length) {
      return false;
    }
    for (final item in question.matchingItems) {
      final value = draft[item.label];
      if (value == null || value.isEmpty) {
        return false;
      }
    }
    return true;
  }

  bool get canSubmit {
    if (hasSubmittedCurrentAnswer || _isSaving) {
      return false;
    }
    if (currentQuestion.isMatching) {
      return _matchingDraftComplete(currentQuestion);
    }
    return _draftChoice?.isNotEmpty ?? false;
  }

  bool get isCurrentQuestionMultipart =>
      _multipartGroupFor(currentQuestion).length > 1;

  bool get isCurrentQuestionLastPart {
    final group = _multipartGroupFor(currentQuestion);
    return group.isEmpty || group.last.id == currentQuestion.id;
  }

  bool get shouldUseNextPartAction =>
      isCurrentQuestionMultipart && !isCurrentQuestionLastPart;

  bool get canAdvanceToNextPart {
    if (readOnlyAfterExam) {
      return !_isSaving && _nextMultipartPartIndexFor(currentQuestion) != null;
    }
    if (_isSaving || _nextMultipartPartIndexFor(currentQuestion) == null) {
      return false;
    }
    if (hasSubmittedCurrentAnswer) {
      return true;
    }
    if (currentQuestion.isMatching) {
      return _matchingDraftComplete(currentQuestion);
    }
    return _draftChoice?.isNotEmpty ?? false;
  }

  bool get canGoPrevious => _currentIndex > 0;

  bool get canGoNext => _currentIndex < _questions.length - 1;

  bool get isSaving => _isSaving;

  bool get canUndoCurrentAnswer =>
      !readOnlyAfterExam && !_isSaving && hasSubmittedCurrentAnswer;

  void selectChoice(String choice) {
    if (readOnlyAfterExam) {
      return;
    }
    if (hasSubmittedCurrentAnswer) {
      return;
    }
    _draftChoice = choice;
    notifyListeners();
  }

  /// Set the choice letter selected for a single matching-question item.
  void selectMatchingChoice(String itemLabel, String choiceKey) {
    if (readOnlyAfterExam) {
      return;
    }
    if (hasSubmittedCurrentAnswer) {
      return;
    }
    final question = currentQuestion;
    if (!question.isMatching) {
      return;
    }
    if (!question.choices.containsKey(choiceKey)) {
      return;
    }
    if (!question.matchingItems.any((item) => item.label == itemLabel)) {
      return;
    }
    final draft = Map<String, String>.from(
      _draftItemSelections[question.id] ?? const <String, String>{},
    );
    draft[itemLabel] = choiceKey;
    _draftItemSelections[question.id] = draft;
    notifyListeners();
  }

  Future<void> undoCurrentAnswer() async {
    if (!canUndoCurrentAnswer) {
      return;
    }
    final question = currentQuestion;
    final existing = _progress.answers[question.id];
    if (existing == null) {
      return;
    }

    if (question.isMatching) {
      final selections = existing.itemSelections;
      if (selections != null && selections.isNotEmpty) {
        _draftItemSelections[question.id] = Map<String, String>.from(selections);
      } else {
        _draftItemSelections.remove(question.id);
      }
    } else {
      _draftChoice = existing.selectedChoice;
    }

    final updatedAnswers =
        Map<String, QuestionProgress>.from(_progress.answers)
          ..remove(question.id);
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
    notifyListeners();
  }

  Future<void> submitCurrentAnswer() async {
    if (readOnlyAfterExam) {
      return;
    }
    if (!canSubmit) {
      return;
    }

    if (shouldUseNextPartAction) {
      await submitCurrentPartAndAdvance();
      return;
    }

    await _saveCurrentAnswer(revealAnswer: !deferRevealUntilExamEnd);
  }

  Future<void> submitCurrentPartAndAdvance() async {
    final nextIndex = _nextMultipartPartIndexFor(currentQuestion);
    if (nextIndex == null || _isSaving) {
      return;
    }

    if (readOnlyAfterExam) {
      _currentIndex = nextIndex;
      _draftChoice = null;
      notifyListeners();
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
    if (readOnlyAfterExam) {
      return;
    }
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
    if (readOnlyAfterExam) {
      if (!canGoPrevious) {
        return;
      }
      _currentIndex -= 1;
      _draftChoice = null;
      notifyListeners();
      return;
    }
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
    if (!readOnlyAfterExam) {
      _syncLastVisitedQuestion();
    }
    notifyListeners();
  }

  void jumpToIndex(int index) {
    if (index < 0 || index >= _questions.length || index == _currentIndex) {
      return;
    }
    _currentIndex = index;
    _draftChoice = null;
    if (!readOnlyAfterExam) {
      _syncLastVisitedQuestion();
    }
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
    final answeredAt = DateTime.now();
    final revealedAt = revealAnswer ? answeredAt : null;

    final QuestionProgress questionProgress;
    if (question.isMatching) {
      final draft = Map<String, String>.from(
        _draftItemSelections[question.id] ?? const <String, String>{},
      );
      final allCorrect = question.matchingItems.every(
        (item) => draft[item.label] == item.correctChoice,
      );
      questionProgress = QuestionProgress(
        selectedChoice: '',
        isCorrect: allCorrect,
        answeredAt: answeredAt,
        revealedAt: revealedAt,
        itemSelections: draft,
      );
    } else {
      final choice = _draftChoice!;
      questionProgress = QuestionProgress(
        selectedChoice: choice,
        isCorrect: choice == question.correctChoice,
        answeredAt: answeredAt,
        revealedAt: revealedAt,
      );
    }

    final updatedAnswers = Map<String, QuestionProgress>.from(_progress.answers)
      ..[question.id] = questionProgress;

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
    return multipartStemKey(question);
  }
}
