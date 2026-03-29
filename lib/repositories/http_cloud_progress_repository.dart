import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/progress_models.dart';
import 'cloud_progress_repository.dart';

/// Calls the Vercel [`api/study-progress.js`] route with the Supabase session
/// JWT so progress is read/written with the **service role** on the server.
/// Falls back to [fallback] if the route is unavailable (e.g. env not set).
class HttpPrimaryCloudProgressRepository implements CloudProgressSync {
  HttpPrimaryCloudProgressRepository({
    required this.apiUrl,
    required this.accessToken,
    required this.fallback,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String apiUrl;
  final Future<String?> Function() accessToken;
  final CloudProgressSync fallback;
  final http.Client _http;

  @override
  Future<StudyProgress?> loadProgress({required String userId}) async {
    final token = await accessToken();
    if (token == null || token.isEmpty) {
      return fallback.loadProgress(userId: userId);
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
        if (raw is Map<String, dynamic>) {
          return StudyProgress.fromServerMap(
            Map<String, dynamic>.from(raw),
          );
        }
        if (raw is Map) {
          return StudyProgress.fromServerMap(Map<String, dynamic>.from(raw));
        }
      }
    } catch (_) {}
    return fallback.loadProgress(userId: userId);
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
          return;
        }
      } catch (_) {}
    }
    await fallback.saveProgress(userId: userId, progress: progress);
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
