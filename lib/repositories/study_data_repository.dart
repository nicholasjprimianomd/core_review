import 'dart:convert';

import '../models/study_data_models.dart';
import 'key_value_store.dart';

class StudyDataRepository {
  StudyDataRepository({KeyValueStore? store})
      : _store = store ?? createKeyValueStore(namespace: 'core_review_study_data');

  final KeyValueStore _store;
  static const _key = 'study_data';

  Future<StudyData> load() async {
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) {
      return StudyData.empty;
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return StudyData.fromJson(decoded);
  }

  Future<void> save(StudyData data) async {
    await _store.write(_key, jsonEncode(data.toJson()));
  }
}
