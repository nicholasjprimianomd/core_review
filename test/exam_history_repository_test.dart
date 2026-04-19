import 'package:core_review/features/exam/exam_history_models.dart';
import 'package:core_review/features/exam/exam_history_repository.dart';
import 'package:core_review/features/exam/exam_session_models.dart';
import 'package:core_review/repositories/cloud_exam_history_repository.dart';
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

class _FakeCloud implements CloudExamHistorySync {
  _FakeCloud(this.remote);

  List<ExamHistoryEntry>? remote;
  List<ExamHistoryEntry>? lastSaved;

  @override
  Future<List<ExamHistoryEntry>?> loadEntries({required String userId}) async {
    return remote;
  }

  @override
  Future<void> saveEntries({
    required String userId,
    required List<ExamHistoryEntry> entries,
  }) async {
    lastSaved = entries;
    remote = entries;
  }
}

ExamHistoryEntry _entry(String id, DateTime ended) {
  return ExamHistoryEntry(
    id: id,
    title: 'Exam $id',
    questionIds: const <String>['q1'],
    examMode: ExamMode.test,
    startedAt: ended.subtract(const Duration(minutes: 5)),
    endedAt: ended,
  );
}

void main() {
  test('mergeEntryLists dedupes by id and orders by endedAt desc', () {
    final a = _entry('1', DateTime(2026, 1, 2));
    final b = _entry('2', DateTime(2026, 1, 3));
    final merged = ExamHistoryRepository.mergeEntryLists(
      <ExamHistoryEntry>[a],
      <ExamHistoryEntry>[b],
    );
    expect(merged.map((e) => e.id).toList(), <String>['2', '1']);
  });

  test('guest and signed-in users use separate local keys', () async {
    final store = _MemoryStore();
    String? userId;
    final guestRepo = ExamHistoryRepository(
      store: store,
      userIdProvider: () => userId,
    );
    await guestRepo.prependEntry(_entry('g', DateTime(2026, 1, 1)));
    userId = 'user-1';
    final userRepo = ExamHistoryRepository(
      store: store,
      userIdProvider: () => userId,
    );
    final forUser = await userRepo.loadEntries();
    expect(forUser.single.id, 'g');

    userId = null;
    final backToGuest = await guestRepo.loadEntries();
    expect(backToGuest, isEmpty);
  });

  test('loadEntries merges remote cloud rows for signed-in user', () async {
    final store = _MemoryStore();
    final remote = <ExamHistoryEntry>[
      _entry('cloud', DateTime(2026, 2, 1)),
    ];
    final cloud = _FakeCloud(remote);
    var userId = 'user-1';
    final repo = ExamHistoryRepository(
      store: store,
      cloudExamHistoryRepository: cloud,
      userIdProvider: () => userId,
    );
    await repo.prependEntry(_entry('local', DateTime(2026, 3, 1)));

    final entries = await repo.loadEntries();
    expect(entries.map((e) => e.id).toList(), <String>['local', 'cloud']);
    expect(cloud.lastSaved, isNotNull);
    expect(cloud.lastSaved!.map((e) => e.id).toList(), <String>['local', 'cloud']);
  });
}
