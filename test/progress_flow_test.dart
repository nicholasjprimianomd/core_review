import 'package:core_review/features/progress/progress_repository.dart';
import 'package:core_review/features/quiz/question_controller.dart';
import 'package:core_review/models/book_models.dart';
import 'package:core_review/models/progress_models.dart';
import 'package:core_review/repositories/key_value_store.dart';
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
  late _MemoryKeyValueStore store;

  setUp(() {
    store = _MemoryKeyValueStore();
  });

  test('ProgressRepository saves and reloads progress state', () async {
    final repository = ProgressRepository(store: store);
    final progress = StudyProgress(
      answers: {
        'chapter-1-1': QuestionProgress(
          selectedChoice: 'D',
          isCorrect: true,
          answeredAt: DateTime(2026, 3, 13),
        ),
      },
      lastVisitedQuestionId: 'chapter-1-1',
    );

    await repository.saveProgress(progress);
    final loaded = await repository.loadProgress();

    expect(loaded.lastVisitedQuestionId, 'chapter-1-1');
    expect(loaded.answeredCount, 1);
    expect(loaded.correctCount, 1);
    expect(loaded.answers['chapter-1-1']?.selectedChoice, 'D');
  });

  test('QuestionController persists submitted answers and navigation', () async {
    final repository = ProgressRepository(store: store);
    final questions = const [
      BookQuestion(
        id: 'chapter-1-1',
        bookId: 'book-1',
        bookTitle: 'Core Review Test',
        chapterId: 'chapter-1',
        chapterNumber: 1,
        chapterTitle: 'Basics of Imaging',
        questionNumber: '1',
        order: 1,
        sortOrder: 1,
        prompt: 'Question one?',
        choices: {
          'A': 'Option A',
          'B': 'Option B',
          'C': 'Option C',
          'D': 'Option D',
        },
        correctChoice: 'B',
        explanation: 'Option B is correct.',
        references: [],
        imageAssets: [],
        stemGroup: '1',
      ),
      BookQuestion(
        id: 'chapter-1-2',
        bookId: 'book-1',
        bookTitle: 'Core Review Test',
        chapterId: 'chapter-1',
        chapterNumber: 1,
        chapterTitle: 'Basics of Imaging',
        questionNumber: '2',
        order: 2,
        sortOrder: 2,
        prompt: 'Question two?',
        choices: {
          'A': 'Option A',
          'B': 'Option B',
          'C': 'Option C',
          'D': 'Option D',
        },
        correctChoice: 'A',
        explanation: 'Option A is correct.',
        references: [],
        imageAssets: [],
        stemGroup: '2',
      ),
    ];

    final controller = QuestionController(
      questions: questions,
      progressRepository: repository,
      initialProgress: StudyProgress.empty,
      initialIndex: 0,
    );

    controller.selectChoice('B');
    await controller.submitCurrentAnswer();
    controller.goToNext();

    final loaded = await repository.loadProgress();

    expect(controller.currentIndex, 1);
    expect(loaded.answers['chapter-1-1']?.isCorrect, isTrue);
    expect(loaded.lastVisitedQuestionId, 'chapter-1-2');
  });

  test('QuestionController jumps directly to a selected question', () async {
    final repository = ProgressRepository(store: store);
    final questions = const [
      BookQuestion(
        id: 'chapter-1-1',
        bookId: 'book-1',
        bookTitle: 'Core Review Test',
        chapterId: 'chapter-1',
        chapterNumber: 1,
        chapterTitle: 'Basics of Imaging',
        questionNumber: '1',
        order: 1,
        sortOrder: 1,
        prompt: 'Question one?',
        choices: {
          'A': 'Option A',
          'B': 'Option B',
        },
        correctChoice: 'A',
        explanation: 'Option A is correct.',
        references: [],
        imageAssets: [],
        stemGroup: '1',
      ),
      BookQuestion(
        id: 'chapter-1-2',
        bookId: 'book-1',
        bookTitle: 'Core Review Test',
        chapterId: 'chapter-1',
        chapterNumber: 1,
        chapterTitle: 'Basics of Imaging',
        questionNumber: '2',
        order: 2,
        sortOrder: 2,
        prompt: 'Question two?',
        choices: {
          'A': 'Option A',
          'B': 'Option B',
        },
        correctChoice: 'B',
        explanation: 'Option B is correct.',
        references: [],
        imageAssets: [],
        stemGroup: '2',
      ),
    ];

    final controller = QuestionController(
      questions: questions,
      progressRepository: repository,
      initialProgress: StudyProgress.empty,
      initialIndex: 0,
    );

    controller.jumpToIndex(1);
    final loaded = await repository.loadProgress();

    expect(controller.currentIndex, 1);
    expect(loaded.lastVisitedQuestionId, 'chapter-1-2');
  });
}
