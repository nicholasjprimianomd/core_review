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
    final questionsRaw = await rootBundle.loadString(
      'assets/data/questions.json',
    );

    return BookContent.fromJson(
      booksJson: jsonDecode(booksRaw) as List<dynamic>,
      topicsJson: jsonDecode(topicsRaw) as List<dynamic>,
      chaptersJson: jsonDecode(chaptersRaw) as List<dynamic>,
      questionsJson: jsonDecode(questionsRaw) as List<dynamic>,
    );
  }
}
