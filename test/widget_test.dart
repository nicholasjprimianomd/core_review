import 'package:core_review/features/books/book_library_screen.dart';
import 'package:core_review/models/book_models.dart';
import 'package:core_review/models/progress_models.dart';
import 'package:core_review/models/study_data_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Book library screen renders multi-book structure', (
    WidgetTester tester,
  ) async {
    final progressListenable = ValueNotifier<StudyProgress>(
      StudyProgress(
        answers: {
          'thoracic-imaging-1-1': QuestionProgress(
            selectedChoice: 'D',
            isCorrect: true,
            answeredAt: DateTime(2026, 3, 13),
            revealedAt: DateTime(2026, 3, 13),
          ),
        },
      ),
    );
    addTearDown(progressListenable.dispose);

    final content = BookContent(
      books: const [
        ReviewBook(
          id: 'thoracic-imaging',
          title: 'Thoracic Imaging',
          sourceFileName: 'Thoracic Imaging - A Core Review.pdf',
          order: 1,
          topicIds: [],
          chapterIds: ['thoracic-imaging-chapter-1'],
          questionIds: ['thoracic-imaging-1-1'],
        ),
      ],
      topics: const [],
      chapters: const [
        BookChapter(
          id: 'thoracic-imaging-chapter-1',
          bookId: 'thoracic-imaging',
          bookTitle: 'Thoracic Imaging',
          number: 1,
          title: 'Basics of Imaging',
          questionIds: ['thoracic-imaging-1-1'],
          sections: [],
        ),
      ],
      questions: const [
        BookQuestion(
          id: 'thoracic-imaging-1-1',
          bookId: 'thoracic-imaging',
          bookTitle: 'Thoracic Imaging',
          chapterId: 'thoracic-imaging-chapter-1',
          chapterNumber: 1,
          chapterTitle: 'Basics of Imaging',
          questionNumber: '1',
          order: 1,
          sortOrder: 1,
          prompt: 'What is the best course of action?',
          choices: {
            'A': 'Observe',
            'B': 'Escalate',
            'C': 'Image',
            'D': 'Consult',
          },
          correctChoice: 'D',
          explanation: 'Escalate care when findings worsen.',
          references: ['ACR Manual on Contrast Media'],
          imageAssets: [],
          stemGroup: '1',
        ),
      ],
    );

    final studyDataListenable = ValueNotifier<StudyData>(StudyData.empty);
    addTearDown(studyDataListenable.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: BookLibraryScreen(
          content: content,
          progressListenable: progressListenable,
          studyDataListenable: studyDataListenable,
          themeMode: ThemeMode.dark,
          currentUserEmail: 'reader@example.com',
          onToggleTheme: () {},
          onOpenAuth: () {},
          onOpenProgress: () {},
          onOpenAnalytics: () {},
          onOpenSearch: () {},
          onOpenBook: (_) {},
          onStartStudySet: (title, questions) async {},
          onOpenCustomExam: () async {},
          onOpenExamHistory: () async {},
          onOpenFontSettings: () async {},
        ),
      ),
    );

    expect(find.text('Core Review'), findsOneWidget);
    expect(find.text('Thoracic Imaging'), findsOneWidget);
    expect(find.text('Browse topics'), findsOneWidget);
    expect(find.text('1 of 1 answered, 1 correct'), findsOneWidget);
    expect(find.text('reader@example.com'), findsOneWidget);
  });
}
