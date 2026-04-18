import 'package:core_review/features/quiz/answer_reveal_panel.dart';
import 'package:core_review/models/book_models.dart';
import 'package:core_review/models/progress_models.dart';
import 'package:core_review/widgets/book_image_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BookContent _singleQuestionContent(BookQuestion q) {
  return BookContent(books: const [], topics: const [], chapters: const [], questions: [q]);
}

void main() {
  testWidgets(
      'reveal panel does not re-render stem-only case images in explanation', (
    WidgetTester tester,
  ) async {
    const q = BookQuestion(
      id: 't-1',
      bookId: 'b',
      bookTitle: 'Book',
      chapterId: 'c',
      chapterNumber: 1,
      chapterTitle: 'Ch',
      questionNumber: '1',
      order: 1,
      sortOrder: 1,
      prompt: 'Prompt?',
      choices: {'A': 'One', 'B': 'Two'},
      correctChoice: 'A',
      explanation: 'Discussion text for the answer.',
      references: [],
      imageAssets: ['assets/book_images/case_only.png'],
      explanationImageAssets: [],
      stemGroup: '1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnswerRevealPanel(
            content: _singleQuestionContent(q),
            question: q,
            progress: QuestionProgress(
              selectedChoice: 'A',
              isCorrect: true,
              answeredAt: DateTime(2026, 1, 1),
              revealedAt: DateTime(2026, 1, 1),
            ),
            explanationHighlights: const [],
            onExplanationHighlightsChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Discussion text'), findsOneWidget);
    expect(find.byType(BookImageGallery), findsNothing);
    expect(find.text('Case images'), findsNothing);
    expect(find.text('Explanation figures'), findsNothing);
  });

  testWidgets(
      'reveal panel shows only explanation-only figures, not case images', (
    WidgetTester tester,
  ) async {
    const q = BookQuestion(
      id: 't-2',
      bookId: 'b',
      bookTitle: 'Book',
      chapterId: 'c',
      chapterNumber: 1,
      chapterTitle: 'Ch',
      questionNumber: '2',
      order: 1,
      sortOrder: 1,
      prompt: 'Prompt?',
      choices: {'A': 'One', 'B': 'Two'},
      correctChoice: 'A',
      explanation: 'Long explanation.',
      references: [],
      imageAssets: ['assets/book_images/stem.png'],
      explanationImageAssets: [
        'assets/book_images/stem.png',
        'assets/book_images/exp_extra.png',
      ],
      stemGroup: '2',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnswerRevealPanel(
            content: _singleQuestionContent(q),
            question: q,
            progress: QuestionProgress(
              selectedChoice: 'A',
              isCorrect: false,
              answeredAt: DateTime(2026, 1, 1),
              revealedAt: DateTime(2026, 1, 1),
            ),
            explanationHighlights: const [],
            onExplanationHighlightsChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Case images'), findsNothing);
    expect(find.text('Explanation figures'), findsOneWidget);
    final galleries = tester.widgetList<BookImageGallery>(
      find.byType(BookImageGallery),
    );
    expect(galleries.length, 1);
    expect(galleries.single.imageAssets, ['assets/book_images/exp_extra.png']);
  });

  testWidgets(
      'reveal panel omits stem-only images even when inherited from multipart sibling', (
    WidgetTester tester,
  ) async {
    const qA = BookQuestion(
      id: 't-7a',
      bookId: 'b',
      bookTitle: 'Book',
      chapterId: 'c',
      chapterNumber: 1,
      chapterTitle: 'Ch',
      questionNumber: '7a',
      order: 1,
      sortOrder: 1,
      prompt: 'First?',
      choices: {'A': 'One', 'B': 'Two'},
      correctChoice: 'A',
      explanation: '',
      references: [],
      imageAssets: ['assets/book_images/shared_stem.png'],
      explanationImageAssets: [],
      stemGroup: '7',
    );
    const qB = BookQuestion(
      id: 't-7b',
      bookId: 'b',
      bookTitle: 'Book',
      chapterId: 'c',
      chapterNumber: 1,
      chapterTitle: 'Ch',
      questionNumber: '7b',
      order: 2,
      sortOrder: 2,
      prompt: 'Second?',
      choices: {'A': 'One', 'B': 'Two'},
      correctChoice: 'A',
      explanation: 'Shared explanation text.',
      references: [],
      imageAssets: [],
      explanationImageAssets: [],
      stemGroup: '7',
    );

    final content = BookContent(
      books: const [],
      topics: const [],
      chapters: const [],
      questions: const [qA, qB],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnswerRevealPanel(
            content: content,
            question: qB,
            progress: QuestionProgress(
              selectedChoice: 'A',
              isCorrect: true,
              answeredAt: DateTime(2026, 1, 1),
              revealedAt: DateTime(2026, 1, 1),
            ),
            explanationHighlights: const [],
            onExplanationHighlightsChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(BookImageGallery), findsNothing);
    expect(find.text('Case images'), findsNothing);
    expect(find.text('Explanation figures'), findsNothing);
  });
}
