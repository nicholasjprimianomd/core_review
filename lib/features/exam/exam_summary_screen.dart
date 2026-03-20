import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import 'exam_session_models.dart';

class ExamSummaryScreen extends StatelessWidget {
  const ExamSummaryScreen({
    required this.title,
    required this.questions,
    required this.progress,
    required this.startedAt,
    required this.endedAt,
    required this.examMode,
    this.timeLimit,
    super.key,
  });

  final String title;
  final List<BookQuestion> questions;
  final StudyProgress progress;
  final DateTime startedAt;
  final DateTime endedAt;
  final ExamMode examMode;
  final Duration? timeLimit;

  @override
  Widget build(BuildContext context) {
    final answered = questions
        .where((q) => progress.answers.containsKey(q.id))
        .length;
    final revealed = questions
        .where((q) => progress.answers[q.id]?.isRevealed ?? false)
        .length;
    final correct = questions
        .where((q) {
          final p = progress.answers[q.id];
          return p != null && p.isRevealed && p.isCorrect;
        })
        .length;
    final accuracy = revealed == 0 ? 0.0 : correct / revealed;
    final elapsed = endedAt.difference(startedAt);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam summary'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            examMode == ExamMode.test ? 'Test mode' : 'Tutor mode',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          _StatRow(label: 'Questions in block', value: '${questions.length}'),
          _StatRow(label: 'Answered', value: '$answered / ${questions.length}'),
          _StatRow(label: 'Graded (revealed)', value: '$revealed'),
          _StatRow(label: 'Correct', value: '$correct'),
          _StatRow(
            label: 'Accuracy (on graded)',
            value: '${(accuracy * 100).toStringAsFixed(1)}%',
          ),
          _StatRow(
            label: 'Time used',
            value: _formatDuration(elapsed),
          ),
          if (timeLimit != null)
            _StatRow(
              label: 'Time allowed',
              value: _formatDuration(timeLimit!),
            ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
