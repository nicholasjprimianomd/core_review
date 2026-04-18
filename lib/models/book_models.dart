class BookContent {
  BookContent({
    required this.books,
    required this.topics,
    required this.chapters,
    required this.questions,
  }) : _bookById = {for (final book in books) book.id: book},
       _topicById = {for (final topic in topics) topic.id: topic},
       _chapterById = {for (final chapter in chapters) chapter.id: chapter},
       _questionById = {
         for (final question in questions) question.id: question,
       };

  final List<ReviewBook> books;
  final List<ReviewTopic> topics;
  final List<BookChapter> chapters;
  final List<BookQuestion> questions;

  final Map<String, ReviewBook> _bookById;
  final Map<String, ReviewTopic> _topicById;
  final Map<String, BookChapter> _chapterById;
  final Map<String, BookQuestion> _questionById;

  ReviewBook bookById(String bookId) {
    final book = _bookById[bookId];
    if (book == null) {
      throw StateError('Book not found: $bookId');
    }
    return book;
  }

  ReviewTopic topicById(String topicId) {
    final topic = _topicById[topicId];
    if (topic == null) {
      throw StateError('Topic not found: $topicId');
    }
    return topic;
  }

  BookChapter chapterById(String chapterId) {
    final chapter = _chapterById[chapterId];
    if (chapter == null) {
      throw StateError('Chapter not found: $chapterId');
    }
    return chapter;
  }

  BookQuestion questionById(String questionId) {
    final question = _questionById[questionId];
    if (question == null) {
      throw StateError('Question not found: $questionId');
    }
    return question;
  }

  List<ReviewBook> booksOrdered() {
    return List<ReviewBook>.from(books)
      ..sort((left, right) => left.order.compareTo(right.order));
  }

  List<ReviewTopic> topicsForBook(String bookId) {
    return topics
        .where((topic) => topic.bookId == bookId)
        .toList(growable: false)
      ..sort((left, right) => left.order.compareTo(right.order));
  }

  List<BookChapter> chaptersForBook(String bookId) {
    return chapters
        .where((chapter) => chapter.bookId == bookId)
        .toList(growable: false)
      ..sort((left, right) => left.number.compareTo(right.number));
  }

  List<BookChapter> chaptersForTopic(String topicId) {
    return chapters
        .where((chapter) => chapter.topicId == topicId)
        .toList(growable: false)
      ..sort((left, right) => left.number.compareTo(right.number));
  }

  List<BookQuestion> questionsForBook(String bookId) {
    return questions
        .where((question) => question.bookId == bookId)
        .toList(growable: false)
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
  }

  List<BookQuestion> questionsForTopic(String topicId) {
    return questions
        .where((question) => question.topicId == topicId)
        .toList(growable: false)
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
  }

  List<BookQuestion> questionsForIds(Iterable<String> questionIds) {
    return questionIds.map(questionById).toList(growable: false)
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
  }

  /// Same as [questionsForIds] but keeps the caller's order (e.g. exam question order).
  List<BookQuestion> questionsForIdsInOrder(Iterable<String> questionIds) {
    return questionIds.map(questionById).toList(growable: false);
  }

  List<BookQuestion> questionsForChapter(String chapterId) {
    return questions
        .where((question) => question.chapterId == chapterId)
        .toList(growable: false)
      ..sort((left, right) => left.order.compareTo(right.order));
  }

  List<BookQuestion> questionsForSection(String sectionId) {
    return questions
        .where((question) => question.sectionId == sectionId)
        .toList(growable: false)
      ..sort((left, right) => left.order.compareTo(right.order));
  }

  /// Same multipart stem bucket as [multipartStemKey] (shared case / 7a–7b rows).
  List<BookQuestion> stemGroupMembers(BookQuestion question) {
    final key = multipartStemKey(question);
    final members = questions
        .where((q) => multipartStemKey(q) == key)
        .toList(growable: false)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return members;
  }

  /// Stem images to display for this specific question part.
  ///
  /// If the question has its own [BookQuestion.imageAssets], those are
  /// returned as-is so each part of a multipart question only shows the
  /// figure that belongs to it. If the part carries no images of its
  /// own, fall back to the stem-group union so short follow-up parts
  /// (e.g. "Given the previous image, what is the diagnosis?") still
  /// inherit the setup question's case images.
  List<String> stemImageAssetsForQuestion(BookQuestion question) {
    for (final p in question.imageAssets) {
      if (p.trim().isNotEmpty) {
        return question.imageAssets;
      }
    }
    return stemGroupImageAssetsMerged(question);
  }

  /// Explanation-only images (not already in the stem set) for this
  /// specific question part. Uses the part's own
  /// [BookQuestion.explanationImageAssets] when non-empty, else falls
  /// back to the stem-group union for inheritance.
  List<String> explanationOnlyImageAssetsForQuestion(BookQuestion question) {
    final stemSet = <String>{
      for (final p in stemImageAssetsForQuestion(question))
        if (p.trim().isNotEmpty) p.trim(),
    };
    final source = <String>[];
    var hasOwn = false;
    for (final p in question.explanationImageAssets) {
      if (p.trim().isNotEmpty) {
        hasOwn = true;
        break;
      }
    }
    if (hasOwn) {
      source.addAll(question.explanationImageAssets);
    } else {
      source.addAll(stemGroupExplanationImageAssetsMerged(question));
    }
    final seen = <String>{};
    final out = <String>[];
    for (final p in source) {
      final t = p.trim();
      if (t.isEmpty || stemSet.contains(t) || !seen.add(t)) {
        continue;
      }
      out.add(p);
    }
    return out;
  }

  /// Union of [BookQuestion.imageAssets] across the stem group; order follows part order, deduped.
  List<String> stemGroupImageAssetsMerged(BookQuestion question) {
    final seen = <String>{};
    final out = <String>[];
    for (final q in stemGroupMembers(question)) {
      for (final p in q.imageAssets) {
        final t = p.trim();
        if (t.isEmpty || !seen.add(t)) {
          continue;
        }
        out.add(p);
      }
    }
    return out;
  }

  /// Union of [BookQuestion.explanationImageAssets] across the stem group.
  List<String> stemGroupExplanationImageAssetsMerged(BookQuestion question) {
    final seen = <String>{};
    final out = <String>[];
    for (final q in stemGroupMembers(question)) {
      for (final p in q.explanationImageAssets) {
        final t = p.trim();
        if (t.isEmpty || !seen.add(t)) {
          continue;
        }
        out.add(p);
      }
    }
    return out;
  }

  /// Stem-group images first, then explanation images (deduped), same idea as [BookQuestion.revealImageAssetsOrdered].
  List<String> revealImageAssetsOrderedForStemGroup(BookQuestion question) {
    final seen = <String>{};
    final out = <String>[];
    for (final p in stemGroupImageAssetsMerged(question)) {
      final t = p.trim();
      if (t.isEmpty || !seen.add(t)) {
        continue;
      }
      out.add(p);
    }
    for (final p in stemGroupExplanationImageAssetsMerged(question)) {
      final t = p.trim();
      if (t.isEmpty || !seen.add(t)) {
        continue;
      }
      out.add(p);
    }
    return out;
  }

  /// Explanation-only paths for this stem group (not duplicated in merged stem set).
  List<String> explanationOnlyImageAssetsForStemGroup(BookQuestion question) {
    final stemSet = <String>{
      for (final p in stemGroupImageAssetsMerged(question))
        if (p.trim().isNotEmpty) p.trim(),
    };
    final seen = <String>{};
    final out = <String>[];
    for (final p in stemGroupExplanationImageAssetsMerged(question)) {
      final t = p.trim();
      if (t.isEmpty || stemSet.contains(t) || !seen.add(t)) {
        continue;
      }
      out.add(p);
    }
    return out;
  }

  bool shouldSplitRevealImageSectionsForStemGroup(BookQuestion question) {
    final stem = stemGroupImageAssetsMerged(question);
    final exp = stemGroupExplanationImageAssetsMerged(question);
    final expOnly = explanationOnlyImageAssetsForStemGroup(question);
    return stem.isNotEmpty && exp.isNotEmpty && expOnly.isNotEmpty;
  }

  factory BookContent.fromJson({
    required List<dynamic> booksJson,
    required List<dynamic> topicsJson,
    required List<dynamic> chaptersJson,
    required List<dynamic> questionsJson,
  }) {
    return BookContent(
      books: booksJson
          .map((entry) => ReviewBook.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false),
      topics: topicsJson
          .map((entry) => ReviewTopic.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false),
      chapters: chaptersJson
          .map((entry) => BookChapter.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false),
      questions: questionsJson
          .map((entry) => BookQuestion.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class ReviewBook {
  const ReviewBook({
    required this.id,
    required this.title,
    required this.sourceFileName,
    required this.order,
    required this.topicIds,
    required this.chapterIds,
    required this.questionIds,
  });

  final String id;
  final String title;
  final String sourceFileName;
  final int order;
  final List<String> topicIds;
  final List<String> chapterIds;
  final List<String> questionIds;

  bool get hasTopics => topicIds.isNotEmpty;

  factory ReviewBook.fromJson(Map<String, dynamic> json) {
    return ReviewBook(
      id: json['id'] as String,
      title: json['title'] as String,
      sourceFileName: json['sourceFileName'] as String,
      order: json['order'] as int,
      topicIds: (json['topicIds'] as List<dynamic>? ?? const []).cast<String>(),
      chapterIds: (json['chapterIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      questionIds: (json['questionIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
    );
  }
}

class ReviewTopic {
  const ReviewTopic({
    required this.id,
    required this.bookId,
    required this.title,
    required this.order,
    required this.chapterIds,
    required this.questionIds,
  });

  final String id;
  final String bookId;
  final String title;
  final int order;
  final List<String> chapterIds;
  final List<String> questionIds;

  factory ReviewTopic.fromJson(Map<String, dynamic> json) {
    return ReviewTopic(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      title: json['title'] as String,
      order: json['order'] as int,
      chapterIds: (json['chapterIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      questionIds: (json['questionIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
    );
  }
}

class BookChapter {
  const BookChapter({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.number,
    required this.title,
    required this.questionIds,
    required this.sections,
    this.topicId,
    this.topicTitle,
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final String? topicId;
  final String? topicTitle;
  final int number;
  final String title;
  final List<String> questionIds;
  final List<BookSection> sections;

  String get displayTitle => '$number. $title';

  bool get hasSections => sections.isNotEmpty;

  int get questionCount {
    if (sections.isEmpty) {
      return questionIds.length;
    }

    return sections.fold<int>(
      0,
      (total, section) => total + section.questionIds.length,
    );
  }

  factory BookChapter.fromJson(Map<String, dynamic> json) {
    return BookChapter(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      bookTitle: json['bookTitle'] as String,
      topicId: json['topicId'] as String?,
      topicTitle: json['topicTitle'] as String?,
      number: json['number'] as int,
      title: json['title'] as String,
      questionIds: (json['questionIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      sections: (json['sections'] as List<dynamic>? ?? const [])
          .map((entry) => BookSection.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class BookSection {
  const BookSection({
    required this.id,
    required this.chapterId,
    required this.number,
    required this.title,
    required this.questionIds,
  });

  final String id;
  final String chapterId;
  final int number;
  final String title;
  final List<String> questionIds;

  String get displayTitle => number > 0 ? 'Section $number: $title' : title;

  factory BookSection.fromJson(Map<String, dynamic> json) {
    return BookSection(
      id: json['id'] as String,
      chapterId: json['chapterId'] as String,
      number: json['number'] as int,
      title: json['title'] as String,
      questionIds: (json['questionIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
    );
  }
}

List<MatchingItem> _parseMatchingItems(Object? raw) {
  if (raw is! List) {
    return const <MatchingItem>[];
  }
  final items = <MatchingItem>[];
  for (final entry in raw) {
    if (entry is Map) {
      items.add(MatchingItem.fromJson(Map<String, dynamic>.from(entry)));
    }
  }
  return List<MatchingItem>.unmodifiable(items);
}

class MatchingItem {
  const MatchingItem({
    required this.label,
    required this.correctChoice,
    this.imageAsset = '',
  });

  final String label;
  final String correctChoice;
  final String imageAsset;

  bool get hasImage => imageAsset.isNotEmpty;

  factory MatchingItem.fromJson(Map<String, dynamic> json) {
    return MatchingItem(
      label: (json['label'] as String?) ?? '',
      correctChoice: (json['correctChoice'] as String?) ?? '',
      imageAsset: (json['imageAsset'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'label': label,
      'correctChoice': correctChoice,
      'imageAsset': imageAsset,
    };
  }
}

class BookQuestion {
  const BookQuestion({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.chapterId,
    required this.chapterNumber,
    required this.chapterTitle,
    required this.questionNumber,
    required this.order,
    required this.sortOrder,
    required this.prompt,
    required this.choices,
    required this.correctChoice,
    required this.explanation,
    required this.references,
    required this.imageAssets,
    this.explanationImageAssets = const <String>[],
    required this.stemGroup,
    this.topicId,
    this.topicTitle,
    this.sectionId,
    this.sectionTitle,
    this.questionType = 'single',
    this.matchingItems = const <MatchingItem>[],
    this.examChain,
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final String? topicId;
  final String? topicTitle;
  final String chapterId;
  final int chapterNumber;
  final String chapterTitle;
  final String? sectionId;
  final String? sectionTitle;
  final String questionNumber;
  final int order;
  final int sortOrder;
  final String prompt;
  final Map<String, String> choices;
  final String correctChoice;
  final String explanation;
  final List<String> references;
  final List<String> imageAssets;
  final List<String> explanationImageAssets;
  final String stemGroup;
  final String questionType;
  final List<MatchingItem> matchingItems;

  /// Optional identifier grouping questions that depend on earlier questions
  /// (e.g. a multi-question clinical case spanning different [questionNumber]s).
  /// Used by the custom exam builder to keep dependent questions contiguous.
  /// Null/empty when the question is standalone.
  final String? examChain;

  String get displayNumber => questionNumber;

  String get correctChoiceText => choices[correctChoice] ?? '';

  bool get hasImages => imageAssets.isNotEmpty;

  bool get hasExplanationImages => explanationImageAssets.isNotEmpty;

  /// True when the question is a matching question with usable per-item pairs.
  bool get isMatching =>
      questionType == 'matching' &&
      matchingItems.isNotEmpty &&
      matchingItems.every((item) => item.correctChoice.isNotEmpty);

  /// Stem [imageAssets] first, then [explanationImageAssets] not already listed (deduped).
  List<String> get revealImageAssetsOrdered {
    final seen = <String>{};
    final out = <String>[];
    for (final p in imageAssets) {
      final t = p.trim();
      if (t.isEmpty || !seen.add(t)) {
        continue;
      }
      out.add(p);
    }
    for (final p in explanationImageAssets) {
      final t = p.trim();
      if (t.isEmpty || !seen.add(t)) {
        continue;
      }
      out.add(p);
    }
    return out;
  }

  bool get hasRevealImages => revealImageAssetsOrdered.isNotEmpty;

  /// Explanation figures that are not also stem [imageAssets].
  List<String> get explanationOnlyImageAssets {
    final stem = <String>{};
    for (final p in imageAssets) {
      final t = p.trim();
      if (t.isNotEmpty) {
        stem.add(t);
      }
    }
    final out = <String>[];
    final seen = <String>{};
    for (final p in explanationImageAssets) {
      final t = p.trim();
      if (t.isEmpty || stem.contains(t) || !seen.add(t)) {
        continue;
      }
      out.add(p);
    }
    return out;
  }

  /// When true, show separate "Case images" and "Explanation figures" blocks.
  bool get shouldSplitRevealImageSections =>
      imageAssets.isNotEmpty &&
      explanationImageAssets.isNotEmpty &&
      explanationOnlyImageAssets.isNotEmpty;

  List<String> get stemImageAssetsDeduped {
    final seen = <String>{};
    final out = <String>[];
    for (final p in imageAssets) {
      final t = p.trim();
      if (t.isEmpty || !seen.add(t)) {
        continue;
      }
      out.add(p);
    }
    return out;
  }

  factory BookQuestion.fromJson(Map<String, dynamic> json) {
    return BookQuestion(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      bookTitle: json['bookTitle'] as String,
      topicId: json['topicId'] as String?,
      topicTitle: json['topicTitle'] as String?,
      chapterId: json['chapterId'] as String,
      chapterNumber: json['chapterNumber'] as int,
      chapterTitle: json['chapterTitle'] as String,
      sectionId: json['sectionId'] as String?,
      sectionTitle: json['sectionTitle'] as String?,
      questionNumber: json['questionNumber'] as String,
      order: json['order'] as int,
      sortOrder: json['sortOrder'] as int,
      prompt: json['prompt'] as String,
      choices: (json['choices'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as String),
      ),
      correctChoice: json['correctChoice'] as String,
      explanation: json['explanation'] as String,
      references: (json['references'] as List<dynamic>? ?? const [])
          .cast<String>(),
      imageAssets: (json['imageAssets'] as List<dynamic>? ?? const [])
          .cast<String>(),
      explanationImageAssets:
          (json['explanationImageAssets'] as List<dynamic>? ?? const [])
              .cast<String>(),
      stemGroup: json['stemGroup'] as String,
      questionType: (json['questionType'] as String?) ?? 'single',
      matchingItems: _parseMatchingItems(json['matchingItems']),
      examChain: (json['examChain'] as String?)?.trim().isNotEmpty == true
          ? (json['examChain'] as String).trim()
          : null,
    );
  }
}

/// Groups parts of the same stem for custom exams (random order) and in-quiz navigation.
///
/// [BookQuestion.stemGroup] repeats per chapter in the books; scoping by [chapterId]
/// and [sectionId] prevents unrelated questions from merging while keeping multipart
/// rows (e.g. 10a/10b) together when they share a stem in the same chapter.
String multipartStemKey(BookQuestion question) {
  final sec = question.sectionId ?? '';
  return '${question.bookId}::${question.chapterId}::$sec::${question.stemGroup}';
}
