import 'package:core_review/features/progress/progress_library_stats.dart';
import 'package:core_review/models/book_models.dart';
import 'package:core_review/models/progress_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orphanedRecords counts keys not in library', () {
    final content = BookContent(
      books: const [
        ReviewBook(
          id: 'b1',
          title: 'B',
          sourceFileName: 'b.json',
          order: 1,
          topicIds: [],
          chapterIds: ['c1'],
          questionIds: ['q1'],
        ),
      ],
      topics: const [],
      chapters: const [
        BookChapter(
          id: 'c1',
          bookId: 'b1',
          bookTitle: 'B',
          number: 1,
          title: 'C',
          questionIds: ['q1'],
          sections: [],
        ),
      ],
      questions: const [
        BookQuestion(
          id: 'q1',
          bookId: 'b1',
          bookTitle: 'B',
          chapterId: 'c1',
          chapterNumber: 1,
          chapterTitle: 'C',
          questionNumber: '1',
          order: 1,
          sortOrder: 1,
          prompt: '?',
          choices: {'A': 'a'},
          correctChoice: 'A',
          explanation: '',
          references: [],
          imageAssets: [],
          stemGroup: '1',
        ),
      ],
    );

    final progress = StudyProgress(
      answers: {
        'q1': QuestionProgress(
          selectedChoice: 'A',
          isCorrect: true,
          answeredAt: DateTime(2026, 3, 1),
          revealedAt: DateTime(2026, 3, 1),
        ),
        'gone-id': QuestionProgress(
          selectedChoice: 'B',
          isCorrect: false,
          answeredAt: DateTime(2026, 3, 2),
          revealedAt: DateTime(2026, 3, 2),
        ),
      },
    );

    final stats = ProgressLibraryStats.compute(content, progress);
    expect(stats.answeredInLibrary, 1);
    expect(stats.orphanedRecords, 1);
    expect(stats.correctInLibrary, 1);
    expect(stats.revealedInLibrary, 1);
  });
}
