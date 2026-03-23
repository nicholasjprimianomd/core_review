import 'dart:math';

import 'package:core_review/features/exam/exam_pool_builder.dart';
import 'package:core_review/features/exam/exam_session_models.dart';
import 'package:core_review/models/book_models.dart';
import 'package:core_review/models/progress_models.dart';
import 'package:flutter_test/flutter_test.dart';

BookContent _content(List<BookQuestion> questions, {List<BookChapter>? chapters}) {
  final chapterList = chapters ??
      [
        BookChapter(
          id: 'c1',
          bookId: 'b1',
          bookTitle: 'B',
          number: 1,
          title: 'Ch',
          questionIds: questions.map((q) => q.id).toList(),
          sections: const [],
        ),
      ];
  return BookContent(
    books: [
      ReviewBook(
        id: 'b1',
        title: 'B',
        sourceFileName: 'x.pdf',
        order: 1,
        topicIds: const [],
        chapterIds: chapterList.map((c) => c.id).toList(),
        questionIds: questions.map((q) => q.id).toList(),
      ),
    ],
    topics: const [],
    chapters: chapterList,
    questions: questions,
  );
}

const BookQuestion _q1a = BookQuestion(
  id: 'm-1-a',
  bookId: '',
  bookTitle: 'B',
  chapterId: 'c1',
  chapterNumber: 1,
  chapterTitle: 'Ch',
  questionNumber: '1',
  order: 1,
  sortOrder: 1,
  prompt: '1a',
  choices: {'A': 'a', 'B': 'b'},
  correctChoice: 'A',
  explanation: '',
  references: [],
  imageAssets: [],
  stemGroup: 'stem1',
);

const BookQuestion _q1b = BookQuestion(
  id: 'm-1-b',
  bookId: '',
  bookTitle: 'B',
  chapterId: 'c1',
  chapterNumber: 1,
  chapterTitle: 'Ch',
  questionNumber: '2',
  order: 2,
  sortOrder: 2,
  prompt: '1b',
  choices: {'A': 'a', 'B': 'b'},
  correctChoice: 'B',
  explanation: '',
  references: [],
  imageAssets: [],
  stemGroup: 'stem1',
);

const BookQuestion _q2 = BookQuestion(
  id: 's-2',
  bookId: '',
  bookTitle: 'B',
  chapterId: 'c1',
  chapterNumber: 1,
  chapterTitle: 'Ch',
  questionNumber: '3',
  order: 3,
  sortOrder: 3,
  prompt: 'single',
  choices: {'A': 'a', 'B': 'b'},
  correctChoice: 'A',
  explanation: '',
  references: [],
  imageAssets: [],
  stemGroup: 'stem2',
);

BookQuestion _withBookId(BookQuestion q, String bookId) {
  return BookQuestion(
    id: q.id,
    bookId: bookId,
    bookTitle: q.bookTitle,
    chapterId: q.chapterId,
    chapterNumber: q.chapterNumber,
    chapterTitle: q.chapterTitle,
    questionNumber: q.questionNumber,
    order: q.order,
    sortOrder: q.sortOrder,
    prompt: q.prompt,
    choices: q.choices,
    correctChoice: q.correctChoice,
    explanation: q.explanation,
    references: q.references,
    imageAssets: q.imageAssets,
    stemGroup: q.stemGroup,
  );
}

void main() {
  test('buildExamQuestionList includes full stem when both parts in scope', () {
    final questions = [
      _withBookId(_q1a, 'b1'),
      _withBookId(_q1b, 'b1'),
      _withBookId(_q2, 'b1'),
    ];
    final content = _content(questions);
    final selection = ExamScopeSelection(
      bookIds: {'b1'},
      chapterIds: {},
      sectionIds: {},
    );
    final out = buildExamQuestionList(
      content: content,
      selection: selection,
      completionFilter: CompletionFilter.allPool,
      progress: StudyProgress.empty,
      questionCount: 10,
      random: Random(42),
    );
    expect(out.length, 3);
    expect(out.map((q) => q.id).toSet(), {'m-1-a', 'm-1-b', 's-2'});
  });

  test('buildExamQuestionList caps at N without splitting stem', () {
    final questions = [
      _withBookId(_q1a, 'b1'),
      _withBookId(_q1b, 'b1'),
      _withBookId(_q2, 'b1'),
    ];
    final content = _content(questions);
    final selection = ExamScopeSelection(
      bookIds: {'b1'},
      chapterIds: {},
      sectionIds: {},
    );
    final out = buildExamQuestionList(
      content: content,
      selection: selection,
      completionFilter: CompletionFilter.allPool,
      progress: StudyProgress.empty,
      questionCount: 2,
      random: Random(0),
    );
    expect(out.length <= 2, isTrue);
    final hasA = out.any((q) => q.id == 'm-1-a');
    final hasB = out.any((q) => q.id == 'm-1-b');
    expect(hasA == hasB, isTrue);
  });

  test('unansweredOnly excludes answered', () {
    final questions = [
      _withBookId(_q1a, 'b1'),
      _withBookId(_q2, 'b1'),
    ];
    final content = _content(questions);
    final selection = ExamScopeSelection(
      bookIds: {'b1'},
      chapterIds: {},
      sectionIds: {},
    );
    final progress = StudyProgress(
      answers: {
        questions[0].id: QuestionProgress(
          selectedChoice: 'A',
          isCorrect: true,
          answeredAt: DateTime(2026, 1, 1),
        ),
      },
    );
    final out = buildExamQuestionList(
      content: content,
      selection: selection,
      completionFilter: CompletionFilter.unansweredOnly,
      progress: progress,
      questionCount: 10,
      random: Random(1),
    );
    expect(out.every((q) => q.id != questions[0].id), isTrue);
    expect(out.any((q) => q.id == questions[1].id), isTrue);
  });

  test(
    'multipart key is chapter-scoped: other chapter with same stemGroup does not merge',
    () {
    final qOther = _withBookId(
      BookQuestion(
        id: 'm-1-c',
        bookId: '',
        bookTitle: 'B',
        chapterId: 'c2',
        chapterNumber: 2,
        chapterTitle: 'Ch2',
        questionNumber: '1',
        order: 1,
        sortOrder: 1,
        prompt: 'other ch',
        choices: const {'A': 'a', 'B': 'b'},
        correctChoice: 'A',
        explanation: '',
        references: const [],
        imageAssets: const [],
        stemGroup: 'stem1',
      ),
      'b1',
    );
    final qA = _withBookId(_q1a, 'b1');
    final questions = [qA, qOther];
    final content = _content(
      questions,
      chapters: [
        BookChapter(
          id: 'c1',
          bookId: 'b1',
          bookTitle: 'B',
          number: 1,
          title: 'Ch',
          questionIds: [qA.id],
          sections: const [],
        ),
        BookChapter(
          id: 'c2',
          bookId: 'b1',
          bookTitle: 'B',
          number: 2,
          title: 'Ch2',
          questionIds: [qOther.id],
          sections: const [],
        ),
      ],
    );
    final selection = ExamScopeSelection(
      bookIds: {},
      chapterIds: {'c1'},
      sectionIds: {},
    );
    final out = buildExamQuestionList(
      content: content,
      selection: selection,
      completionFilter: CompletionFilter.allPool,
      progress: StudyProgress.empty,
      questionCount: 10,
      random: Random(2),
    );
    // c1-only scope: part in c1 is its own stem group; c2 part is unrelated.
    expect(out.map((q) => q.id).toList(), [qA.id]);
  });

  test('multipart parts in same chapter stay adjacent in exam order', () {
    final questions = [
      _withBookId(_q1b, 'b1'),
      _withBookId(_q1a, 'b1'),
    ];
    final content = _content(questions);
    final selection = ExamScopeSelection(
      bookIds: {'b1'},
      chapterIds: {},
      sectionIds: {},
    );
    final out = buildExamQuestionList(
      content: content,
      selection: selection,
      completionFilter: CompletionFilter.allPool,
      progress: StudyProgress.empty,
      questionCount: 10,
      random: Random(99),
    );
    expect(out.length, 2);
    expect(out[0].id, 'm-1-a');
    expect(out[1].id, 'm-1-b');
  });
}
