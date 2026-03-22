class QuestionStudyData {
  const QuestionStudyData({
    this.isFlagged = false,
    this.note = '',
  });

  final bool isFlagged;
  final String note;

  bool get hasNote => note.isNotEmpty;

  QuestionStudyData copyWith({
    bool? isFlagged,
    String? note,
  }) {
    return QuestionStudyData(
      isFlagged: isFlagged ?? this.isFlagged,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (isFlagged) 'isFlagged': true,
      if (note.isNotEmpty) 'note': note,
    };
  }

  factory QuestionStudyData.fromJson(Map<String, dynamic> json) {
    return QuestionStudyData(
      isFlagged: json['isFlagged'] as bool? ?? false,
      note: json['note'] as String? ?? '',
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
    final isEmpty = !data.isFlagged && !data.hasNote;
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
