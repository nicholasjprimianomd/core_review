import 'package:flutter/foundation.dart';
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

class CloudProgressDiagnostics {
  const CloudProgressDiagnostics({
    this.hasToken = false,
    this.httpRpcCount = 0,
    this.sdkRpcCount = 0,
    this.restCount = 0,
    this.metadataCount = 0,
    this.mergedCloudCount = 0,
    this.status = 'idle',
    this.error,
  });

  static const empty = CloudProgressDiagnostics();

  final bool hasToken;
  final int httpRpcCount;
  final int sdkRpcCount;
  final int restCount;
  final int metadataCount;
  final int mergedCloudCount;
  final String status;
  final String? error;
}

/// Loads progress from `core_review_study_progress` / `user_progress` via
/// PostgREST (no custom RPCs; those are optional in some deployments and can
/// 520 if missing or misconfigured). Merges `user_metadata` when present.
class CloudProgressRepository implements CloudProgressSync {
  static const _table = 'core_review_study_progress';
  static const _legacyTable = 'user_progress';
  static const _metadataKey = 'core_review_progress';
  static const List<String> _progressTables = [_table, _legacyTable];

  CloudProgressRepository(
    this._client, {
    Future<String?> Function()? accessTokenProvider,
  }) : _accessTokenProvider = accessTokenProvider;

  final SupabaseClient _client;
  final Future<String?> Function()? _accessTokenProvider;
  final ValueNotifier<CloudProgressDiagnostics> diagnostics = ValueNotifier(
    CloudProgressDiagnostics.empty,
  );

  @override
  Future<StudyProgress?> loadProgress({required String userId}) async {
    final hasToken = await _hasAccessToken();
    if (!hasToken) {
      diagnostics.value = const CloudProgressDiagnostics(status: 'no_token');
      return null;
    }

    final localSessionUserId = _client.auth.currentSession?.user.id;
    if (localSessionUserId != null && localSessionUserId != userId) {
      diagnostics.value = const CloudProgressDiagnostics(
        hasToken: true,
        status: 'user_mismatch',
      );
      return null;
    }

    final restProgress = await _loadTableProgressRest(userId);

    var metaProgress = StudyProgress.empty;
    try {
      final user = (await _client.auth.getUser()).user;
      if (user != null && user.id == userId) {
        final progressJson = user.userMetadata?[_metadataKey];
        if (progressJson is Map<String, dynamic>) {
          metaProgress = StudyProgress.fromServerMap(
            Map<String, dynamic>.from(progressJson),
          );
        }
      }
    } catch (_) {}

    final combined = StudyProgress.empty.mergeWith(restProgress).mergeWith(metaProgress);

    diagnostics.value = CloudProgressDiagnostics(
      hasToken: true,
      httpRpcCount: 0,
      sdkRpcCount: 0,
      restCount: restProgress.answers.length,
      metadataCount: metaProgress.answers.length,
      mergedCloudCount: combined.answers.length,
      status: combined.answers.isEmpty ? 'empty' : 'ok',
    );

    if (combined.answers.isEmpty) {
      return null;
    }
    return combined;
  }

  Future<StudyProgress> _loadTableProgressRest(String userId) async {
    var acc = StudyProgress.empty;
    for (final table in _progressTables) {
      try {
        final row = await _client
            .from(table)
            .select('progress')
            .eq('user_id', userId)
            .maybeSingle();

        if (row == null || row['progress'] == null) {
          continue;
        }
        final p = row['progress'];
        if (p is Map<String, dynamic>) {
          acc = acc.mergeWith(
            StudyProgress.fromServerMap(Map<String, dynamic>.from(p)),
          );
        } else if (p is Map) {
          acc = acc.mergeWith(
            StudyProgress.fromServerMap(Map<String, dynamic>.from(p)),
          );
        }
      } catch (_) {}
    }
    return acc;
  }

  @override
  Future<void> saveProgress({
    required String userId,
    required StudyProgress progress,
  }) async {
    if (!await _hasAccessToken()) {
      throw StateError('No authenticated Supabase user available.');
    }
    final localSessionUserId = _client.auth.currentSession?.user.id;
    if (localSessionUserId != null && localSessionUserId != userId) {
      throw StateError('No authenticated Supabase user available.');
    }

    final payload = progress.toJson();
    final now = DateTime.now().toUtc().toIso8601String();

    await _upsertProgressTable(userId, payload, now);

    try {
      final user = (await _client.auth.getUser()).user;
      if (user == null || user.id != userId) {
        return;
      }
      final metadata = Map<String, dynamic>.from(
        user.userMetadata ?? <String, dynamic>{},
      );
      metadata[_metadataKey] = payload;
      await _client.auth.updateUser(UserAttributes(data: metadata));
    } catch (_) {}
  }

  Future<void> _upsertProgressTable(
    String userId,
    Map<String, dynamic> payload,
    String updatedAt,
  ) async {
    Object lastError = StateError('No progress table accepted upsert.');
    for (final table in _progressTables) {
      try {
        await _client.from(table).upsert(
          <String, dynamic>{
            'user_id': userId,
            'progress': payload,
            'updated_at': updatedAt,
          },
          onConflict: 'user_id',
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError;
  }

  @override
  Future<void> resetProgress({required String userId}) async {
    if (!await _hasAccessToken()) {
      throw StateError('No authenticated Supabase user available.');
    }
    final localSessionUserId = _client.auth.currentSession?.user.id;
    if (localSessionUserId != null && localSessionUserId != userId) {
      throw StateError('No authenticated Supabase user available.');
    }

    final empty = StudyProgress.empty.toJson();
    final now = DateTime.now().toUtc().toIso8601String();

    await _upsertProgressTable(userId, empty, now);

    try {
      final user = (await _client.auth.getUser()).user;
      if (user == null || user.id != userId) {
        return;
      }
      final metadata = Map<String, dynamic>.from(
        user.userMetadata ?? <String, dynamic>{},
      );
      metadata[_metadataKey] = empty;
      await _client.auth.updateUser(UserAttributes(data: metadata));
    } catch (_) {}
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
