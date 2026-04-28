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
          revealedAt: DateTime(2026, 3, 13),
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

  test(
    'QuestionController persists submitted answers and navigation',
    () async {
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
    },
  );

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
        choices: {'A': 'Option A', 'B': 'Option B'},
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
        choices: {'A': 'Option A', 'B': 'Option B'},
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

  test(
    'QuestionController defers reveal in exam test mode then finishDeferredExamReveals',
    () async {
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
      ];

      final controller = QuestionController(
        questions: questions,
        progressRepository: repository,
        initialProgress: StudyProgress.empty,
        initialIndex: 0,
        deferRevealUntilExamEnd: true,
      );

      expect(controller.hasRevealedCurrentAnswer, isFalse);

      controller.selectChoice('B');
      await controller.submitCurrentAnswer();

      expect(controller.currentQuestionProgress?.isRevealed, isFalse);
      expect(controller.explanationsVisibleForCurrent, isFalse);

      await controller.finishDeferredExamReveals();

      expect(controller.currentQuestionProgress?.isRevealed, isTrue);
      expect(controller.explanationsVisibleForCurrent, isTrue);

      final loaded = await repository.loadProgress();
      expect(loaded.answers['chapter-1-1']?.isRevealed, isTrue);
    },
  );

  test(
    'QuestionController hides explanations until answer is revealed in study mode',
    () async {
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
      ];

      final controller = QuestionController(
        questions: questions,
        progressRepository: repository,
        initialProgress: StudyProgress.empty,
        initialIndex: 0,
      );

      expect(controller.explanationsVisibleForCurrent, isFalse);

      controller.selectChoice('B');
      await controller.submitCurrentAnswer();

      expect(controller.currentQuestionProgress?.isRevealed, isTrue);
      expect(controller.explanationsVisibleForCurrent, isTrue);
    },
  );

  test(
    'QuestionController submitCurrentAnswer keeps multipart on same page',
    () async {
      final repository = ProgressRepository(store: store);
      final questions = const [
        BookQuestion(
          id: 'mp-1a',
          bookId: 'book-1',
          bookTitle: 'Core Review Test',
          chapterId: 'chapter-1',
          chapterNumber: 1,
          chapterTitle: 'Basics of Imaging',
          questionNumber: '1a',
          order: 1,
          sortOrder: 1,
          prompt: 'Multipart part A?',
          choices: {'A': 'Option A', 'B': 'Option B'},
          correctChoice: 'A',
          explanation: 'Shared explanation.',
          references: [],
          imageAssets: [],
          stemGroup: 'stem-mp',
        ),
        BookQuestion(
          id: 'mp-1b',
          bookId: 'book-1',
          bookTitle: 'Core Review Test',
          chapterId: 'chapter-1',
          chapterNumber: 1,
          chapterTitle: 'Basics of Imaging',
          questionNumber: '1b',
          order: 2,
          sortOrder: 2,
          prompt: 'Multipart part B?',
          choices: {'A': 'Option A', 'B': 'Option B'},
          correctChoice: 'B',
          explanation: 'Shared explanation.',
          references: [],
          imageAssets: [],
          stemGroup: 'stem-mp',
        ),
      ];

      final controller = QuestionController(
        questions: questions,
        progressRepository: repository,
        initialProgress: StudyProgress.empty,
        initialIndex: 0,
      );

      expect(controller.shouldUseNextPartAction, isTrue);

      controller.selectChoice('A');
      await controller.submitCurrentAnswer();

      expect(controller.currentIndex, 0);
      expect(controller.currentQuestion.id, 'mp-1a');

      final loaded = await repository.loadProgress();
      expect(loaded.answers['mp-1a']?.selectedChoice, 'A');
      expect(loaded.answers['mp-1a']?.isRevealed, isFalse);
      expect(loaded.lastVisitedQuestionId, 'mp-1a');
    },
  );

  test(
    'QuestionController reveals multipart explanations after all parts answer',
    () async {
      final repository = ProgressRepository(store: store);
      final questions = const [
        BookQuestion(
          id: 'mp-1a',
          bookId: 'book-1',
          bookTitle: 'Core Review Test',
          chapterId: 'chapter-1',
          chapterNumber: 1,
          chapterTitle: 'Basics of Imaging',
          questionNumber: '1a',
          order: 1,
          sortOrder: 1,
          prompt: 'Multipart part A?',
          choices: {'A': 'Option A', 'B': 'Option B'},
          correctChoice: 'A',
          explanation: 'Shared explanation.',
          references: [],
          imageAssets: [],
          stemGroup: 'stem-mp',
        ),
        BookQuestion(
          id: 'mp-1b',
          bookId: 'book-1',
          bookTitle: 'Core Review Test',
          chapterId: 'chapter-1',
          chapterNumber: 1,
          chapterTitle: 'Basics of Imaging',
          questionNumber: '1b',
          order: 2,
          sortOrder: 2,
          prompt: 'Multipart part B?',
          choices: {'A': 'Option A', 'B': 'Option B'},
          correctChoice: 'B',
          explanation: 'Shared explanation.',
          references: [],
          imageAssets: [],
          stemGroup: 'stem-mp',
        ),
      ];

      final controller = QuestionController(
        questions: questions,
        progressRepository: repository,
        initialProgress: StudyProgress.empty,
        initialIndex: 0,
      );

      expect(controller.currentMultipartQuestions.map((q) => q.id), [
        'mp-1a',
        'mp-1b',
      ]);

      controller.selectChoiceFor(questions[0], 'A');
      await controller.submitAnswerFor(questions[0]);

      expect(controller.explanationsVisibleFor(questions[0]), isFalse);
      expect(controller.explanationsVisibleFor(questions[1]), isFalse);

      controller.selectChoiceFor(questions[1], 'B');
      await controller.submitAnswerFor(questions[1]);

      expect(controller.explanationsVisibleFor(questions[0]), isTrue);
      expect(controller.explanationsVisibleFor(questions[1]), isTrue);

      final loaded = await repository.loadProgress();
      expect(loaded.answers['mp-1a']?.isRevealed, isTrue);
      expect(loaded.answers['mp-1b']?.isRevealed, isTrue);
    },
  );

  test(
    'QuestionController groups examChain parts with different stems on one page',
    () async {
      final repository = ProgressRepository(store: store);
      final questions = const [
        BookQuestion(
          id: 'chain-1',
          bookId: 'book-1',
          bookTitle: 'Core Review Test',
          chapterId: 'chapter-1',
          chapterNumber: 1,
          chapterTitle: 'Basics of Imaging',
          questionNumber: '14',
          order: 14,
          sortOrder: 14,
          prompt: 'Initial case question?',
          choices: {'A': 'Option A', 'B': 'Option B'},
          correctChoice: 'A',
          explanation: 'First explanation.',
          references: [],
          imageAssets: [],
          stemGroup: '14',
          examChain: 'case-14',
        ),
        BookQuestion(
          id: 'chain-2',
          bookId: 'book-1',
          bookTitle: 'Core Review Test',
          chapterId: 'chapter-1',
          chapterNumber: 1,
          chapterTitle: 'Basics of Imaging',
          questionNumber: '15',
          order: 15,
          sortOrder: 15,
          prompt: 'Follow-up for the patient in Question 14?',
          choices: {'A': 'Option A', 'B': 'Option B'},
          correctChoice: 'B',
          explanation: 'Second explanation.',
          references: [],
          imageAssets: [],
          stemGroup: '15',
          examChain: 'case-14',
        ),
      ];

      final controller = QuestionController(
        questions: questions,
        progressRepository: repository,
        initialProgress: StudyProgress.empty,
        initialIndex: 0,
      );

      expect(controller.currentMultipartQuestions.map((q) => q.id), [
        'chain-1',
        'chain-2',
      ]);

      controller.selectChoiceFor(questions[0], 'A');
      await controller.submitAnswerFor(questions[0]);
      controller.selectChoiceFor(questions[1], 'B');
      await controller.submitAnswerFor(questions[1]);

      expect(controller.currentIndex, 0);
      expect(controller.explanationsVisibleFor(questions[0]), isTrue);
      expect(controller.explanationsVisibleFor(questions[1]), isTrue);
    },
  );

  test(
    'QuestionController infers previous-question dependency without examChain',
    () async {
      final repository = ProgressRepository(store: store);
      final questions = const [
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
          prompt:
              'Based on the image from the previous question, what is next?',
          choices: {'A': 'Option A', 'B': 'Option B'},
          correctChoice: 'B',
          explanation: 'Second explanation.',
          references: [],
          imageAssets: [],
          stemGroup: '11',
        ),
      ];

      final controller = QuestionController(
        questions: questions,
        progressRepository: repository,
        initialProgress: StudyProgress.empty,
        initialIndex: 0,
      );

      expect(controller.currentMultipartQuestions.map((q) => q.id), [
        'case-10',
        'case-11',
      ]);
    },
  );
}
