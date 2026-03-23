import 'dart:math';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import 'exam_session_models.dart';

String stemGroupKey(BookQuestion question) {
  // Same stemGroup string can span chapters; include only book + stem so
  // multipart stems split across chapters stay one logical group.
  return '${question.bookId}::${question.stemGroup}';
}

/// Returns questions whose geographic scope matches [selection].
List<BookQuestion> questionsInScope(
  BookContent content,
  ExamScopeSelection selection,
) {
  if (selection.isEmpty) {
    return [];
  }

  final inSection = selection.sectionIds.isEmpty
      ? const <BookQuestion>[]
      : content.questions
            .where(
              (q) =>
                  q.sectionId != null &&
                  selection.sectionIds.contains(q.sectionId),
            )
            .toList();

  final inChapter = selection.chapterIds.isEmpty
      ? const <BookQuestion>[]
      : content.questions
            .where((q) => selection.chapterIds.contains(q.chapterId))
            .toList();

  final inBook = selection.bookIds.isEmpty
      ? const <BookQuestion>[]
      : content.questions
            .where((q) => selection.bookIds.contains(q.bookId))
            .toList();

  final byId = <String, BookQuestion>{};
  for (final q in [...inBook, ...inChapter, ...inSection]) {
    byId[q.id] = q;
  }
  final merged = byId.values.toList(growable: false)
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return merged;
}

bool _passesCompletionFilter(
  BookQuestion q,
  CompletionFilter filter,
  StudyProgress progress,
) {
  final entry = progress.answers[q.id];
  switch (filter) {
    case CompletionFilter.allPool:
      return true;
    case CompletionFilter.unansweredOnly:
      return entry == null;
    case CompletionFilter.incorrectOnly:
      return entry != null && entry.isRevealed && !entry.isCorrect;
    case CompletionFilter.answeredOnly:
      return entry != null;
  }
}

/// Full stem groups for [content].
Map<String, List<BookQuestion>> fullStemsByKey(BookContent content) {
  final map = <String, List<BookQuestion>>{};
  for (final q in content.questions) {
    map.putIfAbsent(stemGroupKey(q), () => []).add(q);
  }
  for (final list in map.values) {
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }
  return map;
}

/// Stem groups where every part lies in scope and passes [completionFilter].
List<List<BookQuestion>> eligibleStemGroups({
  required BookContent content,
  required Set<String> inScopeIds,
  required CompletionFilter completionFilter,
  required StudyProgress progress,
}) {
  final fullStems = fullStemsByKey(content);
  final groups = <List<BookQuestion>>[];
  for (final full in fullStems.values) {
    if (full.isEmpty) {
      continue;
    }
    if (!full.every((p) => inScopeIds.contains(p.id))) {
      continue;
    }
    if (!full.every(
      (p) => _passesCompletionFilter(p, completionFilter, progress),
    )) {
      continue;
    }
    groups.add(List<BookQuestion>.from(full));
  }
  return groups;
}

/// Picks up to [questionCount] questions (after stem grouping), omitting any trailing
/// whole group that would exceed the cap.
List<BookQuestion> buildExamQuestionList({
  required BookContent content,
  required ExamScopeSelection selection,
  required CompletionFilter completionFilter,
  required StudyProgress progress,
  required int questionCount,
  Random? random,
}) {
  if (questionCount < 1 || selection.isEmpty) {
    return [];
  }

  final rng = random ?? Random();
  final inScope = questionsInScope(content, selection);
  if (inScope.isEmpty) {
    return [];
  }

  final inScopeIds = inScope.map((q) => q.id).toSet();
  final groups = eligibleStemGroups(
    content: content,
    inScopeIds: inScopeIds,
    completionFilter: completionFilter,
    progress: progress,
  );

  if (groups.isEmpty) {
    return [];
  }

  groups.shuffle(rng);

  final result = <BookQuestion>[];
  for (final group in groups) {
    if (result.length + group.length <= questionCount) {
      result.addAll(group);
    }
  }

  return result;
}

/// Sum of questions in eligible stem groups (upper bound on [buildExamQuestionList] size).
int maxQuestionsAvailableForExam({
  required BookContent content,
  required ExamScopeSelection selection,
  required CompletionFilter completionFilter,
  required StudyProgress progress,
}) {
  if (selection.isEmpty) {
    return 0;
  }
  final inScope = questionsInScope(content, selection);
  if (inScope.isEmpty) {
    return 0;
  }
  final inScopeIds = inScope.map((q) => q.id).toSet();
  final groups = eligibleStemGroups(
    content: content,
    inScopeIds: inScopeIds,
    completionFilter: completionFilter,
    progress: progress,
  );
  var n = 0;
  for (final g in groups) {
    n += g.length;
  }
  return n;
}
