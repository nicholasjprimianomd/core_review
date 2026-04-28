import 'package:core_review/features/progress/progress_repository.dart';
import 'package:core_review/features/quiz/question_screen.dart';
import 'package:core_review/models/book_models.dart';
import 'package:core_review/models/progress_models.dart';
import 'package:core_review/models/study_data_models.dart';
import 'package:core_review/repositories/key_value_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

void main() {
  testWidgets('QuestionScreen renders inferred custom-exam multipart block', (
    tester,
  ) async {
    const questions = [
      BookQuestion(
        id: 'case-10',
        bookId: 'book-1',
        bookTitle: 'Core Review Test',
        chapterId: 'chapter-1',
        chapterNumber: 1,
        chapterTitle: 'Basics of Imaging',
        questionNumber: '10',
        order: 10,
        sortOrder: 10,
        prompt: 'Initial case question?',
        choices: {'A': 'Option A', 'B': 'Option B'},
        correctChoice: 'A',
        explanation: 'First explanation.',
        references: [],
        imageAssets: [],
        stemGroup: '10',
      ),
      BookQuestion(
        id: 'case-11',
        bookId: 'book-1',
        bookTitle: 'Core Review Test',
        chapterId: 'chapter-1',
        chapterNumber: 1,
        chapterTitle: 'Basics of Imaging',
        questionNumber: '11',
        order: 11,
        sortOrder: 11,
        prompt: 'Based on the image from the previous question, what is next?',
        choices: {'A': 'Option A', 'B': 'Option B'},
        correctChoice: 'B',
        explanation: 'Second explanation.',
        references: [],
        imageAssets: [],
        stemGroup: '11',
      ),
    ];
    final content = BookContent(
      books: const [
        ReviewBook(
          id: 'book-1',
          title: 'Core Review Test',
          sourceFileName: 'test.pdf',
          order: 1,
          topicIds: [],
          chapterIds: ['chapter-1'],
          questionIds: ['case-10', 'case-11'],
        ),
      ],
      topics: const [],
      chapters: const [
        BookChapter(
          id: 'chapter-1',
          bookId: 'book-1',
          bookTitle: 'Core Review Test',
          number: 1,
          title: 'Basics of Imaging',
          questionIds: ['case-10', 'case-11'],
          sections: [],
        ),
      ],
      questions: questions,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: QuestionScreen(
          title: 'Custom exam',
          content: content,
          questions: questions,
          progressRepository: ProgressRepository(store: _MemoryKeyValueStore()),
          initialProgress: StudyProgress.empty,
          initialStudyData: StudyData.empty,
          initialIndex: 0,
          themeMode: ThemeMode.light,
          onToggleTheme: () {},
          onProgressChanged: (_) {},
          onStudyDataChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Question 10'), findsOneWidget);
    expect(find.text('Question 11'), findsOneWidget);
    expect(find.text('Initial case question?'), findsOneWidget);
    expect(
      find.text('Based on the image from the previous question, what is next?'),
      findsOneWidget,
    );
  });
}
