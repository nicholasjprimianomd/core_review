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
    final currentUser = _client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      return null;
    }

    final user = (await _client.auth.getUser()).user ?? currentUser;
    if (user.id != userId) {
      return null;
    }

    final progressJson = user.userMetadata?[_progressKey];
    if (progressJson is! Map<String, dynamic>) {
      return null;
    }

    return StudyProgress.fromJson(Map<String, dynamic>.from(progressJson));
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
