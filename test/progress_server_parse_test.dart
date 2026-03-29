import 'package:core_review/models/progress_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('StudyProgress.fromServerMap skips invalid entries', () {
    final p = StudyProgress.fromServerMap({
      'answers': {
        'good': {
          'selectedChoice': 'A',
          'isCorrect': true,
          'answeredAt': '2026-03-01T12:00:00.000',
          'revealedAt': '2026-03-01T12:00:00.000',
        },
        'bad': {
          'selectedChoice': 12,
        },
      },
      'updatedAt': '2026-03-02T12:00:00.000',
    });
    expect(p.answeredCount, 1);
    expect(p.answers['good']?.selectedChoice, 'A');
  });

  test('QuestionProgress.tryParseMap accepts int isCorrect', () {
    final q = QuestionProgress.tryParseMap({
      'selectedChoice': 'D',
      'isCorrect': 0,
      'answeredAt': '2026-03-01T12:00:00.000',
    });
    expect(q, isNotNull);
    expect(q!.isCorrect, isFalse);
  });
}
