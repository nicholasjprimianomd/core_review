import 'dart:async';
import 'dart:convert';

import '../../models/progress_models.dart';
import '../../repositories/cloud_progress_repository.dart';
import '../../repositories/key_value_store.dart';

class ProgressRepository {
  ProgressRepository({
    KeyValueStore? store,
    CloudProgressRepository? cloudProgressRepository,
    String? Function()? userIdProvider,
  })  : _store = store ?? createKeyValueStore(namespace: 'core_review_progress'),
        _cloudProgressRepository = cloudProgressRepository,
        _userIdProvider = userIdProvider;

  final KeyValueStore _store;
  final CloudProgressRepository? _cloudProgressRepository;
  final String? Function()? _userIdProvider;
  Future<void> _pendingWrite = Future<void>.value();

  Future<StudyProgress> loadProgress() async {
    await _pendingWrite.catchError((_) {});
    final localProgress = await _readLocal();
    final userId = _userIdProvider?.call();
    if (userId != null && _cloudProgressRepository != null) {
      try {
        final remoteProgress = await _cloudProgressRepository.loadProgress(
          userId: userId,
        );
        if (remoteProgress != null) {
          final mergedProgress = localProgress.mergeWith(remoteProgress);
          await _writeLocal(mergedProgress);
          if (!_isSameProgress(mergedProgress, remoteProgress)) {
            await _cloudProgressRepository.saveProgress(
              userId: userId,
              progress: mergedProgress,
            );
          }
          return mergedProgress;
        }
      } catch (_) {
        // Fall back to local progress if cloud sync is unavailable.
      }
    }

    return localProgress;
  }

  Future<void> saveProgress(
    StudyProgress progress, {
    bool syncToCloud = true,
  }) {
    _pendingWrite = _pendingWrite
        .catchError((_) {})
        .then((_) => _saveProgressInternal(progress, syncToCloud: syncToCloud));
    return _pendingWrite;
  }

  Future<void> _saveProgressInternal(
    StudyProgress progress, {
    required bool syncToCloud,
  }) async {
    await _writeLocal(progress);

    final userId = _userIdProvider?.call();
    if (syncToCloud && userId != null && _cloudProgressRepository != null) {
      try {
        await _cloudProgressRepository.saveProgress(
          userId: userId,
          progress: progress,
        );
      } catch (_) {
        // Keep local progress even if remote sync fails.
      }
    }
  }

  Future<void> resetProgress() {
    final clearedProgress = StudyProgress(
      answers: const <String, QuestionProgress>{},
      updatedAt: DateTime.now(),
    );
    _pendingWrite = _pendingWrite
        .catchError((_) {})
        .then((_) => _resetProgressInternal(clearedProgress));
    return _pendingWrite;
  }

  Future<void> _resetProgressInternal(StudyProgress clearedProgress) async {
    await _writeLocal(clearedProgress);

    final userId = _userIdProvider?.call();
    if (userId != null && _cloudProgressRepository != null) {
      try {
        await _cloudProgressRepository.resetProgress(userId: userId);
      } catch (_) {
        // Ignore cloud reset failures and preserve local reset.
      }
    }
  }

  Future<StudyProgress> _readLocal() async {
    final raw = await _store.read(_localProgressKey());
    if (raw == null || raw.isEmpty) {
      return StudyProgress.empty;
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return StudyProgress.fromJson(decoded);
  }

  Future<void> _writeLocal(StudyProgress progress) async {
    await _store.write(_localProgressKey(), jsonEncode(progress.toJson()));
  }

  bool _isSameProgress(StudyProgress left, StudyProgress right) {
    if (left.lastVisitedQuestionId != right.lastVisitedQuestionId) {
      return false;
    }
    if (left.updatedAt?.toIso8601String() != right.updatedAt?.toIso8601String()) {
      return false;
    }
    if (left.answers.length != right.answers.length) {
      return false;
    }

    for (final entry in left.answers.entries) {
      final other = right.answers[entry.key];
      if (other == null) {
        return false;
      }
      if (entry.value.selectedChoice != other.selectedChoice ||
          entry.value.isCorrect != other.isCorrect ||
          entry.value.answeredAt.toIso8601String() !=
              other.answeredAt.toIso8601String()) {
        return false;
      }
    }

    return true;
  }

  String _localProgressKey() {
    final userId = _userIdProvider?.call();
    if (userId == null || userId.isEmpty) {
      return 'guest_progress';
    }
    return 'progress_$userId';
  }
}
