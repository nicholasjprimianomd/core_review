import 'text_highlight_utils.dart';

class QuestionStudyData {
  const QuestionStudyData({
    this.isFlagged = false,
    this.note = '',
    this.promptHighlights = const <TextHighlightSpan>[],
    this.choiceHighlights = const <String, List<TextHighlightSpan>>{},
    this.explanationHighlights = const <TextHighlightSpan>[],
  });

  final bool isFlagged;
  final String note;
  final List<TextHighlightSpan> promptHighlights;
  final Map<String, List<TextHighlightSpan>> choiceHighlights;
  final List<TextHighlightSpan> explanationHighlights;

  bool get hasNote => note.isNotEmpty;

  bool get hasAnyHighlights =>
      promptHighlights.isNotEmpty ||
      explanationHighlights.isNotEmpty ||
      choiceHighlights.values.any((l) => l.isNotEmpty);

  QuestionStudyData copyWith({
    bool? isFlagged,
    String? note,
    List<TextHighlightSpan>? promptHighlights,
    Map<String, List<TextHighlightSpan>>? choiceHighlights,
    List<TextHighlightSpan>? explanationHighlights,
  }) {
    return QuestionStudyData(
      isFlagged: isFlagged ?? this.isFlagged,
      note: note ?? this.note,
      promptHighlights: promptHighlights ?? this.promptHighlights,
      choiceHighlights: choiceHighlights ?? this.choiceHighlights,
      explanationHighlights:
          explanationHighlights ?? this.explanationHighlights,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (isFlagged) 'isFlagged': true,
      if (note.isNotEmpty) 'note': note,
      if (promptHighlights.isNotEmpty)
        'promptHighlights': promptHighlights.map((e) => e.toJson()).toList(),
      if (explanationHighlights.isNotEmpty)
        'explanationHighlights':
            explanationHighlights.map((e) => e.toJson()).toList(),
      if (choiceHighlights.isNotEmpty)
        'choiceHighlights': choiceHighlights.map(
          (k, v) => MapEntry(
            k,
            v.map((e) => e.toJson()).toList(),
          ),
        ),
    };
  }

  factory QuestionStudyData.fromJson(Map<String, dynamic> json) {
    final rawChoices = json['choiceHighlights'] as Map<String, dynamic>?;
    final choices = <String, List<TextHighlightSpan>>{};
    if (rawChoices != null) {
      for (final e in rawChoices.entries) {
        final list = textHighlightSpansFromJson(e.value as List<dynamic>?);
        if (list.isNotEmpty) {
          choices[e.key] = list;
        }
      }
    }
    return QuestionStudyData(
      isFlagged: json['isFlagged'] as bool? ?? false,
      note: json['note'] as String? ?? '',
      promptHighlights:
          textHighlightSpansFromJson(json['promptHighlights'] as List<dynamic>?),
      choiceHighlights: choices,
      explanationHighlights: textHighlightSpansFromJson(
        json['explanationHighlights'] as List<dynamic>?,
      ),
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
    final isEmpty =
        !data.isFlagged && !data.hasNote && !data.hasAnyHighlights;
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
