import 'dart:convert';

import 'package:core_review/features/progress/progress_repository.dart';
import 'package:core_review/models/progress_models.dart';
import 'package:core_review/repositories/cloud_progress_repository.dart';
import 'package:core_review/repositories/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements KeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

class _FakeCloud implements CloudProgressSync {
  StudyProgress? remote;

  @override
  Future<StudyProgress?> loadProgress({required String userId}) async =>
      remote;

  @override
  Future<void> saveProgress({
    required String userId,
    required StudyProgress progress,
  }) async {
    remote = progress;
  }

  @override
  Future<void> resetProgress({required String userId}) async {
    remote = StudyProgress.empty;
  }
}

void main() {
  test(
    'logged-in load merges guest_progress with cloud before user key merge',
    () async {
      final store = _MemoryStore();
      final cloud = _FakeCloud();
      cloud.remote = StudyProgress(
        answers: {
          'r-only': QuestionProgress(
            selectedChoice: 'A',
            isCorrect: true,
            answeredAt: DateTime(2026, 3, 20),
            revealedAt: DateTime(2026, 3, 20),
          ),
        },
        updatedAt: DateTime(2026, 3, 20),
      );

      const userId = 'user-1';
      final guestPayload = StudyProgress(
        answers: {
          'g-only': QuestionProgress(
            selectedChoice: 'B',
            isCorrect: false,
            answeredAt: DateTime(2026, 3, 21),
            revealedAt: DateTime(2026, 3, 21),
          ),
        },
        updatedAt: DateTime(2026, 3, 21),
      );
      await store.write(
        'guest_progress',
        jsonEncode(guestPayload.toJson()),
      );

      final repo = ProgressRepository(
        store: store,
        cloudProgressRepository: cloud,
        userIdProvider: () => userId,
      );

      final loaded = await repo.loadProgress();
      expect(loaded.answeredCount, 2);
      expect(loaded.answers.containsKey('r-only'), isTrue);
      expect(loaded.answers.containsKey('g-only'), isTrue);

      final rawGuest = await store.read('guest_progress');
      expect(rawGuest, isNull);

      final rawUser = await store.read('progress_user-1');
      expect(rawUser, isNotNull);
      final roundTrip = StudyProgress.fromJson(
        jsonDecode(rawUser!) as Map<String, dynamic>,
      );
      expect(roundTrip.answeredCount, 2);
    },
  );

  test('save merges with latest remote before upload (no clobber)', () async {
    final store = _MemoryStore();
    final cloud = _FakeCloud();
    cloud.remote = StudyProgress(
      answers: {
        'cloud-only': QuestionProgress(
          selectedChoice: 'C',
          isCorrect: true,
          answeredAt: DateTime(2026, 3, 10),
          revealedAt: DateTime(2026, 3, 10),
        ),
      },
      updatedAt: DateTime(2026, 3, 10),
    );

    const userId = 'user-2';
    final repo = ProgressRepository(
      store: store,
      cloudProgressRepository: cloud,
      userIdProvider: () => userId,
    );

    final sessionOnly = StudyProgress(
      answers: {
        'session-only': QuestionProgress(
          selectedChoice: 'D',
          isCorrect: true,
          answeredAt: DateTime(2026, 3, 22),
          revealedAt: DateTime(2026, 3, 22),
        ),
      },
      updatedAt: DateTime(2026, 3, 22),
    );

    await repo.saveProgress(sessionOnly, syncToCloud: true);

    expect(cloud.remote?.answeredCount, 2);
    expect(cloud.remote?.answers.containsKey('cloud-only'), isTrue);
    expect(cloud.remote?.answers.containsKey('session-only'), isTrue);
  });
}
