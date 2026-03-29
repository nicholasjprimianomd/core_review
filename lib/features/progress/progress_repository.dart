import 'dart:async';
import 'dart:convert';

import '../../models/progress_models.dart';
import '../../repositories/cloud_progress_repository.dart';
import '../../repositories/key_value_store.dart';

class ProgressRepository {
  ProgressRepository({
    KeyValueStore? store,
    CloudProgressSync? cloudProgressRepository,
    String? Function()? userIdProvider,
  })  : _store = store ?? createKeyValueStore(namespace: 'core_review_progress'),
        _cloudProgressRepository = cloudProgressRepository,
        _userIdProvider = userIdProvider;

  final KeyValueStore _store;
  final CloudProgressSync? _cloudProgressRepository;
  final String? Function()? _userIdProvider;
  Future<void> _pendingWrite = Future<void>.value();

  Future<StudyProgress> loadProgress() async {
    await _pendingWrite.catchError((_) {});
    final userId = _userIdProvider?.call();
    StudyProgress localProgress;
    try {
      localProgress = await _readCombinedLocal(userId);
    } catch (_) {
      // Corrupt or unreadable local data must not block cloud merge; otherwise
      // bootstrap can replace progress with empty and the next save overwrites remote.
      localProgress = StudyProgress.empty;
    }
    if (userId != null &&
        userId.isNotEmpty &&
        _cloudProgressRepository != null) {
      try {
        final remoteProgress = await _cloudProgressRepository.loadProgress(
          userId: userId,
        );
        final mergedProgress = StudyProgress.empty
            .mergeWith(remoteProgress ?? StudyProgress.empty)
            .mergeWith(localProgress);
        await _writeLocal(mergedProgress);
        await _store.delete('guest_progress');
        if (remoteProgress == null ||
            !_isSameProgress(mergedProgress, remoteProgress)) {
          await _cloudProgressRepository.saveProgress(
            userId: userId,
            progress: mergedProgress,
          );
        }
        return mergedProgress;
      } catch (_) {
        // Fall back to local progress if cloud sync is unavailable.
      }
    }

    if (userId != null && userId.isNotEmpty) {
      await _writeLocal(localProgress);
      await _store.delete('guest_progress');
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
    final userId = _userIdProvider?.call();
    final cloud = _cloudProgressRepository;
    var toPersist = progress;
    if (syncToCloud &&
        userId != null &&
        userId.isNotEmpty &&
        cloud != null) {
      try {
        final remote = await cloud.loadProgress(userId: userId);
        toPersist = StudyProgress.empty
            .mergeWith(remote ?? StudyProgress.empty)
            .mergeWith(progress);
      } catch (_) {
        // Use in-memory progress if the authoritative read fails.
      }
    }

    await _writeLocal(toPersist);

    if (syncToCloud &&
        userId != null &&
        userId.isNotEmpty &&
        cloud != null) {
      try {
        await cloud.saveProgress(userId: userId, progress: toPersist);
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
    await _store.delete('guest_progress');

    final userId = _userIdProvider?.call();
    if (userId != null && _cloudProgressRepository != null) {
      try {
        await _cloudProgressRepository.resetProgress(userId: userId);
      } catch (_) {
        // Ignore cloud reset failures and preserve local reset.
      }
    }
  }

  Future<StudyProgress> _readCombinedLocal(String? userId) async {
    if (userId == null || userId.isEmpty) {
      return _readRawProgress(_localProgressKey());
    }
    final guest = await _readRawProgress('guest_progress');
    final userLocal = await _readRawProgress('progress_$userId');
    return StudyProgress.empty.mergeWith(guest).mergeWith(userLocal);
  }

  Future<StudyProgress> _readRawProgress(String key) async {
    final raw = await _store.read(key);
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
