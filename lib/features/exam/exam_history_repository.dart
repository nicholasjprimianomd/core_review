import 'dart:convert';

import '../../repositories/cloud_exam_history_repository.dart';
import '../../repositories/key_value_store.dart';
import 'exam_history_models.dart';

class ExamHistoryRepository {
  ExamHistoryRepository({
    KeyValueStore? store,
    CloudExamHistorySync? cloudExamHistoryRepository,
    String? Function()? userIdProvider,
  })  : _store = store ?? createKeyValueStore(namespace: 'core_review_exam_history'),
        _cloud = cloudExamHistoryRepository,
        _userIdProvider = userIdProvider;

  /// Cap for stored lists (local + cloud). Raised so account sync can retain more sessions.
  static const int maxEntries = 200;
  static const _legacyKey = 'entries';
  static const _guestKey = 'guest_entries';

  final KeyValueStore _store;
  final CloudExamHistorySync? _cloud;
  final String? Function()? _userIdProvider;

  String _scopedKey(String? userId) {
    if (userId == null || userId.isEmpty) {
      return _guestKey;
    }
    return 'entries_$userId';
  }

  static List<ExamHistoryEntry> mergeEntryLists(
    List<ExamHistoryEntry> a,
    List<ExamHistoryEntry> b,
  ) {
    final byId = <String, ExamHistoryEntry>{};
    for (final e in <ExamHistoryEntry>[...b, ...a]) {
      final existing = byId[e.id];
      if (existing == null || !e.endedAt.isBefore(existing.endedAt)) {
        byId[e.id] = e;
      }
    }
    final out = byId.values.toList(growable: false);
    out.sort((x, y) => y.endedAt.compareTo(x.endedAt));
    return out;
  }

  static List<ExamHistoryEntry> trimToMax(List<ExamHistoryEntry> list) {
    if (list.length <= maxEntries) {
      return list;
    }
    return list.sublist(0, maxEntries);
  }

  static bool _sameIdsInOrder(List<ExamHistoryEntry> a, List<ExamHistoryEntry> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) {
        return false;
      }
    }
    return true;
  }

  Future<List<ExamHistoryEntry>> loadEntries() async {
    final userId = _userIdProvider?.call();
    final local = await _readCombinedLocal(userId);

    if (userId != null && userId.isNotEmpty) {
      if (_cloud != null) {
        try {
          final remote = await _cloud!.loadEntries(userId: userId);
          var merged = mergeEntryLists(local, remote ?? const <ExamHistoryEntry>[]);
          merged = trimToMax(merged);
          await _writeScoped(userId, merged);
          final remoteTrimmed = remote != null ? trimToMax(remote) : null;
          if (remoteTrimmed == null || !_sameIdsInOrder(merged, remoteTrimmed)) {
            await _cloud!.saveEntries(userId: userId, entries: merged);
          }
          return merged;
        } catch (_) {
          // Fall through: still fold guest/legacy rows into the signed-in bucket.
        }
      }
      final consolidated = trimToMax(local);
      await _writeScoped(userId, consolidated);
      return consolidated;
    }

    return trimToMax(local);
  }

  Future<void> prependEntry(ExamHistoryEntry entry) async {
    final userId = _userIdProvider?.call();
    var existing = await _readCombinedLocal(userId);

    if (userId != null && userId.isNotEmpty && _cloud != null) {
      try {
        final remote = await _cloud!.loadEntries(userId: userId);
        existing = mergeEntryLists(existing, remote ?? const <ExamHistoryEntry>[]);
      } catch (_) {}
    }

    final next = trimToMax(mergeEntryLists(<ExamHistoryEntry>[entry], existing));
    await _writeScoped(userId, next);

    if (userId != null && userId.isNotEmpty && _cloud != null) {
      try {
        await _cloud!.saveEntries(userId: userId, entries: next);
      } catch (_) {
        // Local list is authoritative until the next successful sync.
      }
    }
  }

  Future<List<ExamHistoryEntry>> _readCombinedLocal(String? userId) async {
    if (userId == null || userId.isEmpty) {
      return _readGuestLocal();
    }
    final guest = await _decodeKey(_guestKey);
    final userLocal = await _decodeKey(_scopedKey(userId));
    final legacy = await _decodeKey(_legacyKey);
    return mergeEntryLists(mergeEntryLists(userLocal, guest), legacy);
  }

  Future<List<ExamHistoryEntry>> _readGuestLocal() async {
    final guest = await _decodeKey(_guestKey);
    if (guest.isNotEmpty) {
      return guest;
    }
    return _decodeKey(_legacyKey);
  }

  Future<List<ExamHistoryEntry>> _decodeKey(String key) async {
    final raw = await _store.read(key);
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

  Future<void> _writeScoped(String? userId, List<ExamHistoryEntry> entries) async {
    final encoded = jsonEncode(
      entries.map((e) => e.toJson()).toList(growable: false),
    );
    if (userId == null || userId.isEmpty) {
      await _store.write(_guestKey, encoded);
      await _store.delete(_legacyKey);
      return;
    }
    await _store.write(_scopedKey(userId), encoded);
    await _store.delete(_guestKey);
    await _store.delete(_legacyKey);
  }
}
