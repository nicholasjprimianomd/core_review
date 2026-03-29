class QuestionProgress {
  const QuestionProgress({
    required this.selectedChoice,
    required this.isCorrect,
    required this.answeredAt,
    this.revealedAt,
  });

  final String selectedChoice;
  final bool isCorrect;
  final DateTime answeredAt;
  final DateTime? revealedAt;

  bool get isRevealed => revealedAt != null;

  QuestionProgress copyWith({
    String? selectedChoice,
    bool? isCorrect,
    DateTime? answeredAt,
    DateTime? revealedAt,
    bool clearRevealedAt = false,
  }) {
    return QuestionProgress(
      selectedChoice: selectedChoice ?? this.selectedChoice,
      isCorrect: isCorrect ?? this.isCorrect,
      answeredAt: answeredAt ?? this.answeredAt,
      revealedAt: clearRevealedAt ? null : revealedAt ?? this.revealedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'selectedChoice': selectedChoice,
      'isCorrect': isCorrect,
      'answeredAt': answeredAt.toIso8601String(),
      'revealedAt': revealedAt?.toIso8601String(),
    };
  }

  factory QuestionProgress.fromJson(Map<String, dynamic> json) {
    final answeredAt = DateTime.parse(json['answeredAt'] as String);
    final hasExplicitRevealState = json.containsKey('revealedAt');
    return QuestionProgress(
      selectedChoice: json['selectedChoice'] as String,
      isCorrect: json['isCorrect'] as bool,
      answeredAt: answeredAt,
      revealedAt: hasExplicitRevealState
          ? (json['revealedAt'] == null
                ? null
                : DateTime.parse(json['revealedAt'] as String))
          : answeredAt,
    );
  }
}

class StudyProgress {
  const StudyProgress({
    required this.answers,
    this.lastVisitedQuestionId,
    this.updatedAt,
  });

  final Map<String, QuestionProgress> answers;
  final String? lastVisitedQuestionId;
  final DateTime? updatedAt;

  static const empty = StudyProgress(answers: <String, QuestionProgress>{});

  int get answeredCount => answers.length;

  int get revealedCount =>
      answers.values.where((entry) => entry.isRevealed).length;

  int get correctCount =>
      answers.values
          .where((entry) => entry.isRevealed && entry.isCorrect)
          .length;

  double get accuracy {
    if (revealedCount == 0) {
      return 0;
    }
    return correctCount / revealedCount;
  }

  List<String> get incorrectQuestionIds => answers.entries
      .where((entry) => entry.value.isRevealed && !entry.value.isCorrect)
      .map((entry) => entry.key)
      .toList(growable: false);

  StudyProgress copyWith({
    Map<String, QuestionProgress>? answers,
    String? lastVisitedQuestionId,
    bool clearLastVisitedQuestionId = false,
    DateTime? updatedAt,
    bool touch = false,
  }) {
    return StudyProgress(
      answers: answers ?? this.answers,
      lastVisitedQuestionId: clearLastVisitedQuestionId
          ? null
          : lastVisitedQuestionId ?? this.lastVisitedQuestionId,
      updatedAt: touch ? DateTime.now() : updatedAt ?? this.updatedAt,
    );
  }

  StudyProgress mergeWith(StudyProgress other) {
    if (_shouldPreferReset(this, other)) {
      return this;
    }
    if (_shouldPreferReset(other, this)) {
      return other;
    }

    final mergedAnswers = Map<String, QuestionProgress>.from(answers);
    for (final entry in other.answers.entries) {
      final existing = mergedAnswers[entry.key];
      if (_shouldReplaceQuestionProgress(existing, entry.value)) {
        mergedAnswers[entry.key] = entry.value;
      }
    }

    final newer = _newerOf(this, other);
    final older = identical(newer, this) ? other : this;

    return StudyProgress(
      answers: mergedAnswers,
      lastVisitedQuestionId:
          newer.lastVisitedQuestionId ?? older.lastVisitedQuestionId,
      updatedAt:
          _latestTimestamp(updatedAt, other.updatedAt) ??
          _latestAnsweredAt(mergedAnswers),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'answers': answers.map(
        (questionId, entry) => MapEntry(questionId, entry.toJson()),
      ),
      'lastVisitedQuestionId': lastVisitedQuestionId,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory StudyProgress.fromJson(Map<String, dynamic> json) {
    final rawAnswers =
        json['answers'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return StudyProgress(
      answers: rawAnswers.map(
        (questionId, entry) => MapEntry(
          questionId,
          QuestionProgress.fromJson(entry as Map<String, dynamic>),
        ),
      ),
      lastVisitedQuestionId: json['lastVisitedQuestionId'] as String?,
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );
  }

  static bool _shouldPreferReset(
    StudyProgress candidate,
    StudyProgress other,
  ) {
    // Never take the "reset" shortcut when that would drop answers from the
    // other side (e.g. empty local with a fresh timestamp vs full cloud data).
    if (candidate.answers.isEmpty && other.answers.isNotEmpty) {
      return false;
    }
    if (candidate.answers.isNotEmpty && other.answers.isEmpty) {
      return false;
    }
    final candidateUpdatedAt = candidate.updatedAt;
    final otherUpdatedAt = other.updatedAt;
    if (candidate.answers.isNotEmpty ||
        candidateUpdatedAt == null ||
        candidate.lastVisitedQuestionId != null) {
      return false;
    }
    if (other.answers.isEmpty) {
      return true;
    }
    if (otherUpdatedAt == null) {
      return true;
    }
    return candidateUpdatedAt.isAfter(otherUpdatedAt);
  }

  static StudyProgress _newerOf(StudyProgress left, StudyProgress right) {
    final leftUpdatedAt = left.updatedAt;
    final rightUpdatedAt = right.updatedAt;
    if (leftUpdatedAt != null && rightUpdatedAt != null) {
      if (leftUpdatedAt.isAfter(rightUpdatedAt)) {
        return left;
      }
      if (rightUpdatedAt.isAfter(leftUpdatedAt)) {
        return right;
      }
    } else if (leftUpdatedAt != null) {
      return left;
    } else if (rightUpdatedAt != null) {
      return right;
    }

    if (left.answers.length != right.answers.length) {
      return left.answers.length >= right.answers.length ? left : right;
    }
    if (right.lastVisitedQuestionId != null) {
      return right;
    }
    return left;
  }

  static DateTime? _latestTimestamp(DateTime? left, DateTime? right) {
    if (left == null) {
      return right;
    }
    if (right == null) {
      return left;
    }
    return left.isAfter(right) ? left : right;
  }

  static DateTime? _latestAnsweredAt(Map<String, QuestionProgress> answers) {
    DateTime? latest;
    for (final progress in answers.values) {
      if (latest == null || progress.answeredAt.isAfter(latest)) {
        latest = progress.answeredAt;
      }
    }
    return latest;
  }

  static bool _shouldReplaceQuestionProgress(
    QuestionProgress? existing,
    QuestionProgress incoming,
  ) {
    if (existing == null) {
      return true;
    }
    if (incoming.answeredAt.isAfter(existing.answeredAt)) {
      return true;
    }
    if (existing.answeredAt.isAfter(incoming.answeredAt)) {
      return false;
    }

    final existingRevealedAt = existing.revealedAt;
    final incomingRevealedAt = incoming.revealedAt;
    if (existingRevealedAt == null) {
      return incomingRevealedAt != null;
    }
    if (incomingRevealedAt == null) {
      return false;
    }
    return incomingRevealedAt.isAfter(existingRevealedAt);
  }
}
