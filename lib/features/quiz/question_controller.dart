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
       _multipartGroupKeys = dependentQuestionGroupKeysForQuestions(questions),
       _progressRepository = progressRepository,
       _progress = initialProgress,
       _currentIndex = initialIndex.clamp(0, questions.length - 1) {
    if (!readOnlyAfterExam) {
      _syncLastVisitedQuestion();
    }
  }

  final List<BookQuestion> _questions;
  final Map<String, String> _multipartGroupKeys;
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
  final Map<String, String> _draftChoices = <String, String>{};
  final Map<String, Map<String, String>> _draftItemSelections =
      <String, Map<String, String>>{};
  bool _isSaving = false;
  bool _deferredRevealsCompleted = false;

  List<BookQuestion> get questions => _questions;

  StudyProgress get progress => _progress;

  BookQuestion get currentQuestion => _questions[_currentIndex];

  List<BookQuestion> get currentMultipartQuestions =>
      _multipartGroupFor(currentQuestion);

  QuestionProgress? get currentQuestionProgress =>
      _progress.answers[currentQuestion.id];

  bool get hasRevealedCurrentAnswer =>
      currentQuestionProgress?.isRevealed ?? false;

  bool get deferredRevealsCompleted => _deferredRevealsCompleted;

  bool get explanationsVisibleForCurrent =>
      _deferredRevealsCompleted || hasRevealedCurrentAnswer;

  bool explanationsVisibleFor(BookQuestion question) =>
      _deferredRevealsCompleted ||
      (questionProgressFor(question)?.isRevealed ?? false);

  int get currentIndex => _currentIndex;

  int get questionCount => _questions.length;

  double get completionFraction =>
      questionCount == 0 ? 0 : (_currentIndex + 1) / questionCount;

  String? get selectedChoice => selectedChoiceFor(currentQuestion);

  String? selectedChoiceFor(BookQuestion question) =>
      questionProgressFor(question)?.selectedChoice ??
      _draftChoiceFor(question);

  bool get hasSubmittedCurrentAnswer => currentQuestionProgress != null;

  QuestionProgress? questionProgressFor(BookQuestion question) =>
      _progress.answers[question.id];

  /// Current per-item selections for the active matching question.
  /// Returns the submitted selections when revealed, otherwise the in-progress
  /// draft (possibly empty). The keys are [MatchingItem.label]s.
  Map<String, String> get currentMatchingSelections {
    final question = currentQuestion;
    return matchingSelectionsFor(question);
  }

  Map<String, String> matchingSelectionsFor(BookQuestion question) {
    if (!question.isMatching) {
      return const <String, String>{};
    }
    final submitted = questionProgressFor(question)?.itemSelections;
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
    return canSubmitQuestion(currentQuestion);
  }

  bool canSubmitQuestion(BookQuestion question) {
    if (questionProgressFor(question) != null || _isSaving) {
      return false;
    }
    if (question.isMatching) {
      return _matchingDraftComplete(question);
    }
    return _draftChoiceFor(question)?.isNotEmpty ?? false;
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

  bool get canGoPreviousGroup {
    final group = currentMultipartQuestions;
    final firstIndex = _questions.indexWhere((q) => q.id == group.first.id);
    return firstIndex > 0;
  }

  bool get canGoNextGroup {
    final group = currentMultipartQuestions;
    final lastIndex = _questions.indexWhere((q) => q.id == group.last.id);
    return lastIndex >= 0 && lastIndex < _questions.length - 1;
  }

  bool get isSaving => _isSaving;

  bool get canUndoCurrentAnswer =>
      !readOnlyAfterExam && !_isSaving && hasSubmittedCurrentAnswer;

  bool canUndoQuestion(BookQuestion question) =>
      !readOnlyAfterExam && !_isSaving && questionProgressFor(question) != null;

  void selectChoice(String choice) {
    selectChoiceFor(currentQuestion, choice);
  }

  void selectChoiceFor(BookQuestion question, String choice) {
    if (readOnlyAfterExam || questionProgressFor(question) != null) {
      return;
    }
    _setDraftChoiceFor(question, choice);
    notifyListeners();
  }

  /// Set the choice letter selected for a single matching-question item.
  void selectMatchingChoice(String itemLabel, String choiceKey) {
    selectMatchingChoiceFor(currentQuestion, itemLabel, choiceKey);
  }

  void selectMatchingChoiceFor(
    BookQuestion question,
    String itemLabel,
    String choiceKey,
  ) {
    if (readOnlyAfterExam) {
      return;
    }
    if (questionProgressFor(question) != null) {
      return;
    }
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
    await undoQuestion(currentQuestion);
  }

  Future<void> undoQuestion(BookQuestion question) async {
    if (!canUndoQuestion(question)) {
      return;
    }
    final existing = _progress.answers[question.id];
    if (existing == null) {
      return;
    }

    if (question.isMatching) {
      final selections = existing.itemSelections;
      if (selections != null && selections.isNotEmpty) {
        _draftItemSelections[question.id] = Map<String, String>.from(
          selections,
        );
      } else {
        _draftItemSelections.remove(question.id);
      }
    } else {
      _setDraftChoiceFor(question, existing.selectedChoice);
    }

    final updatedAnswers = Map<String, QuestionProgress>.from(_progress.answers)
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

    await submitAnswerFor(currentQuestion);
  }

  Future<void> submitAnswerFor(BookQuestion question) async {
    if (readOnlyAfterExam || !canSubmitQuestion(question)) {
      return;
    }

    final group = _multipartGroupFor(question);
    final isMultipart = group.length > 1;
    final revealAnswer = !deferRevealUntilExamEnd && !isMultipart;
    await _saveAnswerForQuestion(
      question: question,
      revealAnswer: revealAnswer,
    );

    if (deferRevealUntilExamEnd || !isMultipart) {
      return;
    }

    final allGroupPartsAnswered = group.every(
      (groupQuestion) => _progress.answers.containsKey(groupQuestion.id),
    );
    if (allGroupPartsAnswered) {
      await _revealMultipartGroup(question);
    }
  }

  Future<void> submitCurrentPartAndAdvance() async {
    final nextIndex = _nextMultipartPartIndexFor(currentQuestion);
    if (nextIndex == null || _isSaving) {
      return;
    }

    if (readOnlyAfterExam) {
      _currentIndex = nextIndex;
      _clearActiveDraftChoice();
      notifyListeners();
      return;
    }

    if (hasSubmittedCurrentAnswer) {
      _currentIndex = nextIndex;
      _clearActiveDraftChoice();
      _syncLastVisitedQuestion();
      notifyListeners();
      return;
    }

    if (!canSubmitQuestion(currentQuestion)) {
      return;
    }

    await _saveAnswerForQuestion(
      question: currentQuestion,
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
    final updatedAnswers = Map<String, QuestionProgress>.from(
      _progress.answers,
    );
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
      _clearActiveDraftChoice();
      notifyListeners();
      return;
    }
    if (!canGoPrevious) {
      return;
    }
    _currentIndex -= 1;
    _clearActiveDraftChoice();
    _syncLastVisitedQuestion();
    notifyListeners();
  }

  void goToNext() {
    if (!canGoNext) {
      return;
    }
    _currentIndex += 1;
    _clearActiveDraftChoice();
    if (!readOnlyAfterExam) {
      _syncLastVisitedQuestion();
    }
    notifyListeners();
  }

  void goToPreviousGroup() {
    if (!canGoPreviousGroup) {
      return;
    }
    final group = currentMultipartQuestions;
    final firstIndex = _questions.indexWhere((q) => q.id == group.first.id);
    final target = (firstIndex - 1).clamp(0, _questions.length - 1);
    jumpToIndex(target);
  }

  void goToNextGroup() {
    if (!canGoNextGroup) {
      return;
    }
    final group = currentMultipartQuestions;
    final lastIndex = _questions.indexWhere((q) => q.id == group.last.id);
    final target = (lastIndex + 1).clamp(0, _questions.length - 1);
    jumpToIndex(target);
  }

  void jumpToIndex(int index) {
    if (index < 0 || index >= _questions.length || index == _currentIndex) {
      return;
    }
    _currentIndex = index;
    _clearActiveDraftChoice();
    if (!readOnlyAfterExam) {
      _syncLastVisitedQuestion();
    }
    notifyListeners();
  }

  void _syncLastVisitedQuestion() {
    _progress = _progress.copyWith(lastVisitedQuestionId: currentQuestion.id);
    _publishProgress();
    unawaited(_progressRepository.saveProgress(_progress, syncToCloud: false));
  }

  void _publishProgress() {
    onProgressChanged?.call(_progress);
  }

  Future<void> _saveAnswerForQuestion({
    required BookQuestion question,
    required bool revealAnswer,
    int? nextIndexAfterSave,
  }) async {
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
      final choice = _draftChoiceFor(question)!;
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
      _clearActiveDraftChoice();
      _syncLastVisitedQuestion();
    }
    notifyListeners();
  }

  Future<void> _revealMultipartGroup(BookQuestion question) async {
    final now = DateTime.now();
    final updatedAnswers = Map<String, QuestionProgress>.from(
      _progress.answers,
    );
    _markStemGroupAsRevealed(
      question: question,
      answers: updatedAnswers,
      revealedAt: now,
    );
    _progress = _progress.copyWith(answers: updatedAnswers, touch: true);
    _publishProgress();
    _isSaving = true;
    notifyListeners();

    await _progressRepository.saveProgress(_progress);

    _isSaving = false;
    notifyListeners();
  }

  String? _draftChoiceFor(BookQuestion question) {
    if (question.id == currentQuestion.id) {
      return _draftChoice ?? _draftChoices[question.id];
    }
    return _draftChoices[question.id];
  }

  void _setDraftChoiceFor(BookQuestion question, String choice) {
    _draftChoices[question.id] = choice;
    if (question.id == currentQuestion.id) {
      _draftChoice = choice;
    }
  }

  void _clearActiveDraftChoice() {
    _draftChoice = _draftChoices[currentQuestion.id];
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
    return _multipartGroupKeys[question.id] ??
        dependentQuestionGroupKey(question);
  }
}
