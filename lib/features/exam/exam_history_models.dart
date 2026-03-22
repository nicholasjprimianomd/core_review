import 'exam_session_models.dart';

class ExamHistoryEntry {
  const ExamHistoryEntry({
    required this.id,
    required this.title,
    required this.questionIds,
    required this.examMode,
    required this.startedAt,
    required this.endedAt,
    this.timeLimitSeconds,
  });

  final String id;
  final String title;
  final List<String> questionIds;
  final ExamMode examMode;
  final DateTime startedAt;
  final DateTime endedAt;
  final int? timeLimitSeconds;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'questionIds': questionIds,
      'examMode': examMode.name,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt.toIso8601String(),
      'timeLimitSeconds': timeLimitSeconds,
    };
  }

  factory ExamHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawIds = json['questionIds'] as List<dynamic>? ?? <dynamic>[];
    return ExamHistoryEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      questionIds: rawIds.map((e) => e as String).toList(growable: false),
      examMode: ExamMode.values.byName(json['examMode'] as String),
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: DateTime.parse(json['endedAt'] as String),
      timeLimitSeconds: json['timeLimitSeconds'] as int?,
    );
  }
}
