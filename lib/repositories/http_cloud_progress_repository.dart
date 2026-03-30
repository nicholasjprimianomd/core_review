import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/progress_models.dart';
import 'cloud_progress_repository.dart';

/// Calls the Vercel `api/study-progress.js` route with the persisted Supabase
/// session JWT so progress is read/written with the service role on the server.
/// Falls back to [fallback] if the route is unavailable.
class HttpPrimaryCloudProgressRepository implements CloudProgressSync {
  HttpPrimaryCloudProgressRepository({
    required this.apiUrl,
    required this.accessToken,
    required this.fallback,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String apiUrl;
  final Future<String?> Function() accessToken;
  final CloudProgressRepository fallback;
  final http.Client _http;

  final ValueNotifier<CloudProgressDiagnostics> diagnostics = ValueNotifier(
    CloudProgressDiagnostics.empty,
  );

  @override
  Future<StudyProgress?> loadProgress({required String userId}) async {
    final token = await accessToken();
    if (token == null || token.isEmpty) {
      final progress = await fallback.loadProgress(userId: userId);
      diagnostics.value = fallback.diagnostics.value;
      return progress;
    }
    try {
      final response = await _http.get(
        Uri.parse(apiUrl),
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = map['progress'];
        StudyProgress? progress;
        if (raw is Map<String, dynamic>) {
          progress = StudyProgress.fromServerMap(
            Map<String, dynamic>.from(raw),
          );
        } else if (raw is Map) {
          progress = StudyProgress.fromServerMap(Map<String, dynamic>.from(raw));
        }
        if (progress != null) {
          diagnostics.value = CloudProgressDiagnostics(
            hasToken: true,
            httpRpcCount: progress.answers.length,
            mergedCloudCount: progress.answers.length,
            status: 'http_primary_ok',
          );
          return progress.answers.isEmpty ? null : progress;
        }
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
      hasToken: d.hasToken || (token.isNotEmpty),
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
    if (token != null && token.isNotEmpty) {
      try {
        final response = await _http.put(
          Uri.parse(apiUrl),
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{'progress': progress.toJson()}),
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
