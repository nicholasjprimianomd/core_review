import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/book_models.dart';

class BookRepository {
  Future<BookContent> loadContent() async {
    final booksRaw = await rootBundle.loadString('assets/data/books.json');
    final topicsRaw = await rootBundle.loadString('assets/data/topics.json');
    final chaptersRaw = await rootBundle.loadString(
      'assets/data/chapters.json',
    );
    final booksJson = jsonDecode(booksRaw) as List<dynamic>;
    final questionsJson = await _loadQuestions(booksJson);

    return BookContent.fromJson(
      booksJson: booksJson,
      topicsJson: jsonDecode(topicsRaw) as List<dynamic>,
      chaptersJson: jsonDecode(chaptersRaw) as List<dynamic>,
      questionsJson: questionsJson,
    );
  }

  Future<List<dynamic>> _loadQuestions(List<dynamic> booksJson) async {
    try {
      final chunkFutures = booksJson.map((bookJson) async {
        final bookId = (bookJson as Map<String, dynamic>)['id'] as String;
        final questionsRaw = await rootBundle.loadString(
          'assets/data/questions/$bookId.json',
        );
        return jsonDecode(questionsRaw) as List<dynamic>;
      }).toList(growable: false);
      final questionChunks = await Future.wait(chunkFutures);
      return [
        for (final chunk in questionChunks) ...chunk,
      ];
    } catch (_) {
      final questionsRaw = await rootBundle.loadString(
        'assets/data/questions.json',
      );
      return jsonDecode(questionsRaw) as List<dynamic>;
    }
  }
}
