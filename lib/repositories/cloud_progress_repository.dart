import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import '../config/app_config.dart';
import '../models/progress_models.dart';

abstract class CloudProgressSync {
  Future<StudyProgress?> loadProgress({required String userId});

  Future<void> saveProgress({
    required String userId,
    required StudyProgress progress,
  });

  Future<void> resetProgress({required String userId});
}

/// Loads full progress via Postgres RPC (`get_my_study_progress`) so RLS/jwt
/// timing on direct table reads cannot return empty rows while Auth still
/// works. Merges `user_metadata` for legacy drift. Parses JSON with
/// [StudyProgress.fromServerMap] so one bad answer does not drop hundreds.
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

    var tableProgress = await _loadTableProgressHttp();
    if (tableProgress.answers.isEmpty) {
      tableProgress = await _loadTableProgressRpc();
    }
    if (tableProgress.answers.isEmpty) {
      final rest = await _loadTableProgressRest(userId);
      tableProgress = rest ?? StudyProgress.empty;
    }

    var metaProgress = StudyProgress.empty;
    final progressJson = user.userMetadata?[_metadataKey];
    if (progressJson is Map<String, dynamic>) {
      metaProgress = StudyProgress.fromServerMap(
        Map<String, dynamic>.from(progressJson),
      );
    }

    final combined = StudyProgress.empty
        .mergeWith(tableProgress)
        .mergeWith(metaProgress);

    if (combined.answers.isEmpty) {
      return null;
    }
    return combined;
  }

  Future<StudyProgress> _loadTableProgressHttp() async {
    try {
      final response = await http.post(
        _rpcUri('get_my_study_progress'),
        headers: await _rpcHeaders(),
        body: const JsonEncoder().convert(<String, dynamic>{}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return StudyProgress.empty;
      }
      final raw = jsonDecode(response.body);
      if (raw is Map<String, dynamic>) {
        return StudyProgress.fromServerMap(raw);
      }
      if (raw is Map) {
        return StudyProgress.fromServerMap(Map<String, dynamic>.from(raw));
      }
    } catch (_) {}
    return StudyProgress.empty;
  }

  Future<StudyProgress> _loadTableProgressRpc() async {
    try {
      final raw = await _client.rpc('get_my_study_progress');
      if (raw == null) {
        return StudyProgress.empty;
      }
      if (raw is Map<String, dynamic>) {
        return StudyProgress.fromServerMap(raw);
      }
      if (raw is Map) {
        return StudyProgress.fromServerMap(Map<String, dynamic>.from(raw));
      }
    } catch (_) {}
    return StudyProgress.empty;
  }

  Future<StudyProgress?> _loadTableProgressRest(String userId) async {
    try {
      final row = await _client
          .from(_table)
          .select('progress')
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null || row['progress'] == null) {
        return null;
      }
      final p = row['progress'];
      if (p is Map<String, dynamic>) {
        return StudyProgress.fromServerMap(
          Map<String, dynamic>.from(p),
        );
      }
      if (p is Map) {
        return StudyProgress.fromServerMap(Map<String, dynamic>.from(p));
      }
    } catch (_) {}
    return null;
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

    try {
      final response = await http.post(
        _rpcUri('upsert_my_study_progress'),
        headers: await _rpcHeaders(),
        body: jsonEncode(<String, dynamic>{'payload': payload}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP RPC upsert failed: ${response.statusCode}');
      }
    } catch (_) {
      try {
        await _client.rpc(
          'upsert_my_study_progress',
          params: <String, dynamic>{'payload': payload},
        );
      } catch (_) {
        await _client.from(_table).upsert(
          <String, dynamic>{
            'user_id': userId,
            'progress': payload,
            'updated_at': now,
          },
          onConflict: 'user_id',
        );
      }
    }

    try {
      final metadata = Map<String, dynamic>.from(
        user.userMetadata ?? <String, dynamic>{},
      );
      metadata[_metadataKey] = payload;
      await _client.auth.updateUser(UserAttributes(data: metadata));
    } catch (_) {}
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

    try {
      final response = await http.post(
        _rpcUri('clear_my_study_progress'),
        headers: await _rpcHeaders(),
        body: const JsonEncoder().convert(<String, dynamic>{}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP RPC clear failed: ${response.statusCode}');
      }
    } catch (_) {
      try {
        await _client.rpc('clear_my_study_progress');
      } catch (_) {
        await _client.from(_table).upsert(
          <String, dynamic>{
            'user_id': userId,
            'progress': empty,
            'updated_at': now,
          },
          onConflict: 'user_id',
        );
      }
    }

    try {
      final metadata = Map<String, dynamic>.from(
        user.userMetadata ?? <String, dynamic>{},
      );
      metadata[_metadataKey] = empty;
      await _client.auth.updateUser(UserAttributes(data: metadata));
    } catch (_) {}
  }

  Uri _rpcUri(String functionName) =>
      Uri.parse('${AppConfig.supabaseUrl}/rest/v1/rpc/$functionName');

  Future<Map<String, String>> _rpcHeaders() async {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw AuthSessionMissingException();
    }
    return <String, String>{
      'apikey': AppConfig.supabaseAnonKey,
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }
}
