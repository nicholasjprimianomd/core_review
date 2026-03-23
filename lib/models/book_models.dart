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
    required this.stemGroup,
    this.topicId,
    this.topicTitle,
    this.sectionId,
    this.sectionTitle,
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
  final String stemGroup;

  String get displayNumber => questionNumber;

  String get correctChoiceText => choices[correctChoice] ?? '';

  bool get hasImages => imageAssets.isNotEmpty;

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
      stemGroup: json['stemGroup'] as String,
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
