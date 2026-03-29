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
/// available. Always merges [core_review_study_progress] with
/// `user_metadata.core_review_progress` so JWT-sized partial metadata and the
/// table cannot drift (e.g. 136 + 336 keys).
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

    var tableProgress = StudyProgress.empty;
    try {
      final row = await _client
          .from(_table)
          .select('progress')
          .eq('user_id', userId)
          .maybeSingle();

      if (row != null && row['progress'] is Map<String, dynamic>) {
        final decoded =
            Map<String, dynamic>.from(row['progress'] as Map<String, dynamic>);
        tableProgress = StudyProgress.fromJson(decoded);
      }
    } catch (_) {}

    var metaProgress = StudyProgress.empty;
    final progressJson = user.userMetadata?[_metadataKey];
    if (progressJson is Map<String, dynamic>) {
      try {
        metaProgress =
            StudyProgress.fromJson(Map<String, dynamic>.from(progressJson));
      } catch (_) {}
    }

    final combined = StudyProgress.empty
        .mergeWith(tableProgress)
        .mergeWith(metaProgress);

    if (combined.answers.isEmpty) {
      return null;
    }
    return combined;
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
