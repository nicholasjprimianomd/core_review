import 'dart:convert';

import '../../repositories/key_value_store.dart';
import 'exam_history_models.dart';

class ExamHistoryRepository {
  ExamHistoryRepository({KeyValueStore? store})
    : _store = store ?? createKeyValueStore(namespace: 'core_review_exam_history');

  static const int maxEntries = 50;
  static const _key = 'entries';

  final KeyValueStore _store;

  Future<List<ExamHistoryEntry>> loadEntries() async {
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) {
      return <ExamHistoryEntry>[];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => ExamHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return <ExamHistoryEntry>[];
    }
  }

  Future<void> prependEntry(ExamHistoryEntry entry) async {
    final existing = await loadEntries();
    final next = <ExamHistoryEntry>[entry, ...existing];
    if (next.length > maxEntries) {
      next.removeRange(maxEntries, next.length);
    }
    await _store.write(
      _key,
      jsonEncode(next.map((e) => e.toJson()).toList(growable: false)),
    );
  }
}
