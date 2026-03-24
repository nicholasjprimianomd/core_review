import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../models/book_models.dart';

class AssistantReply {
  const AssistantReply({
    required this.answer,
    required this.searchTerms,
    required this.webImages,
  });

  final String answer;
  final List<String> searchTerms;
  final List<AssistantWebImage> webImages;

  factory AssistantReply.fromJson(Map<String, dynamic> json) {
    return AssistantReply(
      answer: json['answer'] as String? ?? '',
      searchTerms: (json['searchTerms'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      webImages: (json['webImages'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((entry) => AssistantWebImage.fromJson(
                Map<String, dynamic>.from(entry),
              ))
          .toList(growable: false),
    );
  }
}

class AssistantWebImage {
  const AssistantWebImage({
    required this.title,
    required this.caption,
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.sourceUrl,
    required this.sourceLabel,
    required this.query,
  });

  final String title;
  final String caption;
  final String imageUrl;
  final String thumbnailUrl;
  final String sourceUrl;
  final String sourceLabel;
  final String query;

  factory AssistantWebImage.fromJson(Map<String, dynamic> json) {
    return AssistantWebImage(
      title: json['title'] as String? ?? '',
      caption: json['caption'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      sourceLabel: json['sourceLabel'] as String? ?? '',
      query: json['query'] as String? ?? '',
    );
  }

  bool get hasImage => imageUrl.isNotEmpty || thumbnailUrl.isNotEmpty;
}

class ReferenceBookMatch {
  const ReferenceBookMatch({
    required this.bookLabel,
    required this.fileName,
    required this.page,
    required this.excerpt,
    required this.fullText,
  });

  final String bookLabel;
  final String fileName;
  final int page;
  final String excerpt;

  /// Full text stored in the index for this PDF page (may be capped when the index was built).
  final String fullText;

  factory ReferenceBookMatch.fromJson(Map<String, dynamic> json) {
    return ReferenceBookMatch(
      bookLabel: json['bookLabel'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      page: (json['page'] as num?)?.toInt() ?? 0,
      excerpt: json['excerpt'] as String? ?? '',
      fullText: json['fullText'] as String? ?? '',
    );
  }
}

class ReferenceBooksSearchResult {
  const ReferenceBooksSearchResult({
    required this.matches,
    this.message,
  });

  final List<ReferenceBookMatch> matches;
  final String? message;

  factory ReferenceBooksSearchResult.fromJson(Map<String, dynamic> json) {
    return ReferenceBooksSearchResult(
      matches: (json['matches'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => ReferenceBookMatch.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      message: json['message'] as String?,
    );
  }
}

class AssistantRepository {
  AssistantRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, AssistantReply> _replyCache = <String, AssistantReply>{};

  Future<AssistantReply> askQuestion({
    required BookQuestion question,
    required String userPrompt,
    required bool allowAnswerReveal,
    bool includeAnswer = true,
    bool includeWebImages = false,
    List<String> searchTerms = const <String>[],
  }) async {
    final trimmedPrompt = userPrompt.trim();
    final normalizedSearchTerms = searchTerms
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    final cacheKey = jsonEncode(<String, dynamic>{
      'questionId': question.id,
      'userPrompt': trimmedPrompt,
      'allowAnswerReveal': allowAnswerReveal,
      'includeAnswer': includeAnswer,
      'includeWebImages': includeWebImages,
      'searchTerms': normalizedSearchTerms,
    });
    final cachedReply = _replyCache[cacheKey];
    if (cachedReply != null) {
      return cachedReply;
    }

    final uri = Uri.parse(AppConfig.resolveAssistantApiUrl());
    final response = await _client
        .post(
          uri,
          headers: const <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'userPrompt': trimmedPrompt,
            'includeAnswer': includeAnswer,
            'includeWebImages': includeWebImages,
            if (normalizedSearchTerms.isNotEmpty) 'searchTerms': normalizedSearchTerms,
            'studyContext': <String, dynamic>{
              'allowAnswerReveal': allowAnswerReveal,
              'questionNumber': question.displayNumber,
              'prompt': question.prompt,
              'choices': question.choices,
              'hasImages': question.hasImages,
              'imageCount': question.imageAssets.length,
              if (allowAnswerReveal) ...<String, dynamic>{
                'correctChoice': question.correctChoice,
                'correctChoiceText': question.correctChoiceText,
                'explanation': question.explanation,
                'references': question.references,
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 75));

    final payload = _decodeResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error'] as String? ??
            'The study assistant request failed with status '
                '${response.statusCode}.',
      );
    }

    final reply = AssistantReply.fromJson(payload);
    _replyCache[cacheKey] = reply;
    return reply;
  }

  /// Search pre-built PDF text index (Crack the Core / War Machine). Only runs when called.
  Future<ReferenceBooksSearchResult> searchReferenceBooks({
    required String query,
  }) async {
    final uri = Uri.parse(AppConfig.resolveReferenceBooksSearchUrl());
    final response = await _client
        .post(
          uri,
          headers: const <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, String>{'query': query}),
        )
        .timeout(const Duration(seconds: 45));

    final payload = _decodeResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error'] as String? ??
            'Reference book search failed (${response.statusCode}).',
      );
    }

    return ReferenceBooksSearchResult.fromJson(payload);
  }

  void dispose() {
    _client.close();
  }

  Map<String, dynamic> _decodeResponse(String body) {
    if (body.trim().isEmpty) {
      return const <String, dynamic>{};
    }

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw const FormatException('Assistant response was not a JSON object.');
  }
}
