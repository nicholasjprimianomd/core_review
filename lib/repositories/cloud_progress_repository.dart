import 'package:supabase/supabase.dart';

import '../models/progress_models.dart';

abstract class CloudProgressSync {
  Future<StudyProgress?> loadProgress({required String userId});

  Future<void> saveProgress({
    required String userId,
    required StudyProgress progress,
  });

  Future<void> resetProgress({required String userId});
}

/// Persists study progress in Postgres (PostgREST) so the full JSON is always
/// returned. `auth.users.user_metadata` is only used as a legacy fallback
/// because large payloads are often missing or truncated in JWT-backed user
/// objects on the client.
class CloudProgressRepository implements CloudProgressSync {
  static const _table = 'core_review_study_progress';
  static const _metadataKey = 'core_review_progress';

  CloudProgressRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<StudyProgress?> loadProgress({required String userId}) async {
    User? user;
    try {
      user = (await _client.auth.getUser()).user;
    } on AuthSessionMissingException {
      return null;
    } catch (_) {
      return null;
    }
    if (user == null || user.id != userId) {
      return null;
    }

    try {
      final row = await _client
          .from(_table)
          .select('progress')
          .eq('user_id', userId)
          .maybeSingle();

      if (row != null) {
        final raw = row['progress'];
        if (raw is Map<String, dynamic>) {
          final decoded = Map<String, dynamic>.from(raw);
          final answers = decoded['answers'];
          if (answers is Map && answers.isNotEmpty) {
            try {
              return StudyProgress.fromJson(decoded);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    return _loadProgressFromUserMetadata(userId);
  }

  Future<StudyProgress?> _loadProgressFromUserMetadata(String userId) async {
    try {
      final user = (await _client.auth.getUser()).user;
      if (user == null || user.id != userId) {
        return null;
      }
      final progressJson = user.userMetadata?[_metadataKey];
      if (progressJson is! Map<String, dynamic>) {
        return null;
      }
      return StudyProgress.fromJson(Map<String, dynamic>.from(progressJson));
    } on AuthSessionMissingException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveProgress({
    required String userId,
    required StudyProgress progress,
  }) async {
    User? user;
    try {
      user = (await _client.auth.getUser()).user;
    } on AuthSessionMissingException {
      throw StateError('No authenticated Supabase user available.');
    } catch (_) {
      throw StateError('No authenticated Supabase user available.');
    }
    if (user == null || user.id != userId) {
      throw StateError('No authenticated Supabase user available.');
    }

    final payload = progress.toJson();
    final now = DateTime.now().toUtc().toIso8601String();

    await _client.from(_table).upsert(
      <String, dynamic>{
        'user_id': userId,
        'progress': payload,
        'updated_at': now,
      },
      onConflict: 'user_id',
    );

    try {
      final metadata = Map<String, dynamic>.from(
        user.userMetadata ?? <String, dynamic>{},
      );
      metadata[_metadataKey] = payload;
      await _client.auth.updateUser(UserAttributes(data: metadata));
    } catch (_) {
      // Table is authoritative; metadata is best-effort backup / old builds.
    }
  }

  @override
  Future<void> resetProgress({required String userId}) async {
    User? user;
    try {
      user = (await _client.auth.getUser()).user;
    } on AuthSessionMissingException {
      throw StateError('No authenticated Supabase user available.');
    } catch (_) {
      throw StateError('No authenticated Supabase user available.');
    }
    if (user == null || user.id != userId) {
      throw StateError('No authenticated Supabase user available.');
    }

    final empty = StudyProgress.empty.toJson();
    final now = DateTime.now().toUtc().toIso8601String();

    await _client.from(_table).upsert(
      <String, dynamic>{
        'user_id': userId,
        'progress': empty,
        'updated_at': now,
      },
      onConflict: 'user_id',
    );

    try {
      final metadata = Map<String, dynamic>.from(
        user.userMetadata ?? <String, dynamic>{},
      );
      metadata[_metadataKey] = empty;
      await _client.auth.updateUser(UserAttributes(data: metadata));
    } catch (_) {}
  }
}
