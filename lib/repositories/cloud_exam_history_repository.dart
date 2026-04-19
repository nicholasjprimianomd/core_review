import 'package:supabase/supabase.dart';

import '../features/exam/exam_history_models.dart';

abstract class CloudExamHistorySync {
  Future<List<ExamHistoryEntry>?> loadEntries({required String userId});

  Future<void> saveEntries({
    required String userId,
    required List<ExamHistoryEntry> entries,
  });
}

/// Persists completed exam summaries in `core_review_exam_history` (PostgREST).
class CloudExamHistoryRepository implements CloudExamHistorySync {
  static const _table = 'core_review_exam_history';

  CloudExamHistoryRepository(
    this._client, {
    Future<String?> Function()? accessTokenProvider,
  }) : _accessTokenProvider = accessTokenProvider;

  final SupabaseClient _client;
  final Future<String?> Function()? _accessTokenProvider;

  @override
  Future<List<ExamHistoryEntry>?> loadEntries({required String userId}) async {
    if (!await _hasAccessToken()) {
      return null;
    }
    final localSessionUserId = _client.auth.currentSession?.user.id;
    if (localSessionUserId != null && localSessionUserId != userId) {
      return null;
    }

    try {
      final row = await _client
          .from(_table)
          .select('entries')
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null || row['entries'] == null) {
        return null;
      }
      final rawEntries = row['entries'];
      if (rawEntries is! List<dynamic>) {
        return null;
      }
      final out = <ExamHistoryEntry>[];
      for (final e in rawEntries) {
        if (e is Map<String, dynamic>) {
          try {
            out.add(ExamHistoryEntry.fromJson(e));
          } catch (_) {}
        } else if (e is Map) {
          try {
            out.add(ExamHistoryEntry.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveEntries({
    required String userId,
    required List<ExamHistoryEntry> entries,
  }) async {
    if (!await _hasAccessToken()) {
      throw StateError('No authenticated Supabase user available.');
    }
    final localSessionUserId = _client.auth.currentSession?.user.id;
    if (localSessionUserId != null && localSessionUserId != userId) {
      throw StateError('No authenticated Supabase user available.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from(_table).upsert(
      <String, dynamic>{
        'user_id': userId,
        'entries': entries.map((e) => e.toJson()).toList(growable: false),
        'updated_at': now,
      },
      onConflict: 'user_id',
    );
  }

  Future<bool> _hasAccessToken() async {
    final token = await _resolveAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<String?> _resolveAccessToken() async {
    final inMemory = _client.auth.currentSession?.accessToken;
    if (inMemory != null && inMemory.isNotEmpty) {
      return inMemory;
    }
    final provider = _accessTokenProvider;
    if (provider == null) {
      return null;
    }
    return await provider();
  }
}
