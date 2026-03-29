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

class CloudProgressRepository implements CloudProgressSync {
  static const _progressKey = 'core_review_progress';

  CloudProgressRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<StudyProgress?> loadProgress({required String userId}) async {
    // Always use GET /user via getUser() so we read user_metadata from the Auth
    // server. Relying on auth.currentUser alone can return null right after
    // recoverSession on web, or a JWT snapshot that does not include full
    // metadata rows for large payloads.
    try {
      final user = (await _client.auth.getUser()).user;
      if (user == null || user.id != userId) {
        return null;
      }

      final progressJson = user.userMetadata?[_progressKey];
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
    await _updateUserMetadata(userId: userId, progress: progress);
  }

  @override
  Future<void> resetProgress({required String userId}) async {
    await _updateUserMetadata(userId: userId, progress: StudyProgress.empty);
  }

  Future<void> _updateUserMetadata({
    required String userId,
    required StudyProgress progress,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null || user.id != userId) {
      throw StateError('No authenticated Supabase user available.');
    }

    final metadata = Map<String, dynamic>.from(
      user.userMetadata ?? <String, dynamic>{},
    );
    metadata[_progressKey] = progress.toJson();

    await _client.auth.updateUser(UserAttributes(data: metadata));
  }
}
