class QuestionStudyData {
  const QuestionStudyData({
    this.isFlagged = false,
    this.note = '',
    this.highlights = const [],
  });

  final bool isFlagged;
  final String note;
  final List<HighlightSpan> highlights;

  bool get hasNote => note.isNotEmpty;
  bool get hasHighlights => highlights.isNotEmpty;

  QuestionStudyData copyWith({
    bool? isFlagged,
    String? note,
    List<HighlightSpan>? highlights,
  }) {
    return QuestionStudyData(
      isFlagged: isFlagged ?? this.isFlagged,
      note: note ?? this.note,
      highlights: highlights ?? this.highlights,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (isFlagged) 'isFlagged': true,
      if (note.isNotEmpty) 'note': note,
      if (highlights.isNotEmpty)
        'highlights': highlights.map((h) => h.toJson()).toList(),
    };
  }

  factory QuestionStudyData.fromJson(Map<String, dynamic> json) {
    return QuestionStudyData(
      isFlagged: json['isFlagged'] as bool? ?? false,
      note: json['note'] as String? ?? '',
      highlights: (json['highlights'] as List<dynamic>?)
              ?.map(
                (entry) => HighlightSpan.fromJson(entry as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );
  }
}

class HighlightSpan {
  const HighlightSpan({
    required this.field,
    required this.start,
    required this.end,
  });

  /// Which text field: 'prompt', 'explanation', or a choice key like 'A'.
  final String field;
  final int start;
  final int end;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'field': field,
      'start': start,
      'end': end,
    };
  }

  factory HighlightSpan.fromJson(Map<String, dynamic> json) {
    return HighlightSpan(
      field: json['field'] as String,
      start: json['start'] as int,
      end: json['end'] as int,
    );
  }
}

class StudyData {
  const StudyData({
    required this.questions,
  });

  final Map<String, QuestionStudyData> questions;

  static const empty = StudyData(questions: <String, QuestionStudyData>{});

  QuestionStudyData forQuestion(String questionId) {
    return questions[questionId] ?? const QuestionStudyData();
  }

  Set<String> get flaggedQuestionIds =>
      questions.entries
          .where((e) => e.value.isFlagged)
          .map((e) => e.key)
          .toSet();

  StudyData withQuestion(String questionId, QuestionStudyData data) {
    final updated = Map<String, QuestionStudyData>.from(questions);
    final isEmpty = !data.isFlagged && !data.hasNote && !data.hasHighlights;
    if (isEmpty) {
      updated.remove(questionId);
    } else {
      updated[questionId] = data;
    }
    return StudyData(questions: updated);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'questions': questions.map(
        (id, data) => MapEntry(id, data.toJson()),
      ),
    };
  }

  factory StudyData.fromJson(Map<String, dynamic> json) {
    final raw = json['questions'] as Map<String, dynamic>? ?? {};
    return StudyData(
      questions: raw.map(
        (id, data) => MapEntry(
          id,
          QuestionStudyData.fromJson(data as Map<String, dynamic>),
        ),
      ),
    );
  }
}
