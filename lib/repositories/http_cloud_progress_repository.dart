import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/progress_models.dart';
import 'cloud_progress_repository.dart';

/// Calls the Vercel `api/study-progress.js` route.
/// Sends tokens in the JSON body (not Authorization headers) so large cookies /
/// header limits do not produce spurious failures (e.g. 494 from the edge).
class HttpPrimaryCloudProgressRepository implements CloudProgressSync {
  HttpPrimaryCloudProgressRepository({
    required this.apiUrl,
    required this.accessToken,
    required this.refreshToken,
    required this.fallback,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String apiUrl;
  final Future<String?> Function() accessToken;
  final Future<String?> Function() refreshToken;
  final CloudProgressRepository fallback;
  final http.Client _http;

  final ValueNotifier<CloudProgressDiagnostics> diagnostics = ValueNotifier(
    CloudProgressDiagnostics.empty,
  );

  static const _jsonHeaders = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Map<String, dynamic> _sessionBody(String? token, String? refresh) {
    return <String, dynamic>{
      if (token != null && token.isNotEmpty) 'access_token': token,
      if (refresh != null && refresh.isNotEmpty) 'refresh_token': refresh,
    };
  }

  @override
  Future<StudyProgress?> loadProgress({required String userId}) async {
    final token = await accessToken();
    final refresh = await refreshToken();
    if (token == null || token.isEmpty) {
      if (refresh == null || refresh.isEmpty) {
        final progress = await fallback.loadProgress(userId: userId);
        diagnostics.value = fallback.diagnostics.value;
        return progress;
      }
    }
    try {
      final body = <String, dynamic>{
        'op': 'load',
        ..._sessionBody(token, refresh),
      };
      final response = await _http.post(
        Uri.parse(apiUrl),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = map['progress'];
        final StudyProgress progress;
        if (raw is Map<String, dynamic>) {
          progress = StudyProgress.fromServerMap(
            Map<String, dynamic>.from(raw),
          );
        } else if (raw is Map) {
          progress = StudyProgress.fromServerMap(Map<String, dynamic>.from(raw));
        } else {
          progress = StudyProgress.empty;
        }
        diagnostics.value = CloudProgressDiagnostics(
          hasToken: true,
          httpRpcCount: progress.answers.length,
          mergedCloudCount: progress.answers.length,
          status: 'http_primary_ok',
        );
        return progress;
      }
      diagnostics.value = CloudProgressDiagnostics(
        hasToken: true,
        status: 'http_primary_${response.statusCode}',
      );
    } catch (error) {
      diagnostics.value = CloudProgressDiagnostics(
        hasToken: true,
        status: 'http_primary_error',
        error: error.toString(),
      );
    }

    final progress = await fallback.loadProgress(userId: userId);
    final d = fallback.diagnostics.value;
    diagnostics.value = CloudProgressDiagnostics(
      hasToken: d.hasToken || ((token?.isNotEmpty ?? false)),
      httpRpcCount: d.httpRpcCount,
      sdkRpcCount: d.sdkRpcCount,
      restCount: d.restCount,
      metadataCount: d.metadataCount,
      mergedCloudCount: d.mergedCloudCount,
      status: 'fallback_${d.status}',
      error: d.error,
    );
    return progress;
  }

  @override
  Future<void> saveProgress({
    required String userId,
    required StudyProgress progress,
  }) async {
    final token = await accessToken();
    final refresh = await refreshToken();
    if ((token != null && token.isNotEmpty) ||
        (refresh != null && refresh.isNotEmpty)) {
      try {
        final body = <String, dynamic>{
          'op': 'save',
          'progress': progress.toJson(),
          ..._sessionBody(token, refresh),
        };
        final response = await _http.post(
          Uri.parse(apiUrl),
          headers: _jsonHeaders,
          body: jsonEncode(body),
        );
        if (response.statusCode == 204 || response.statusCode == 200) {
          diagnostics.value = CloudProgressDiagnostics(
            hasToken: true,
            httpRpcCount: progress.answers.length,
            mergedCloudCount: progress.answers.length,
            status: 'http_primary_save_ok',
          );
          return;
        }
      } catch (_) {}
    }
    await fallback.saveProgress(userId: userId, progress: progress);
    diagnostics.value = fallback.diagnostics.value;
  }

  @override
  Future<void> resetProgress({required String userId}) async {
    final cleared = StudyProgress(
      answers: const <String, QuestionProgress>{},
      updatedAt: DateTime.now(),
    );
    await saveProgress(userId: userId, progress: cleared);
  }
}
