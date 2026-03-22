import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import '../../models/study_data_models.dart';

class AnswerRevealPanel extends StatelessWidget {
  const AnswerRevealPanel({
    required this.question,
    required this.progress,
    required this.highlights,
    required this.onHighlight,
    required this.onRemoveHighlight,
    super.key,
  });

  final BookQuestion question;
  final QuestionProgress progress;
  final List<HighlightSpan> highlights;
  final ValueChanged<HighlightSpan> onHighlight;
  final ValueChanged<HighlightSpan> onRemoveHighlight;

  TextSpan _buildHighlightedSpan({
    required String text,
    required String field,
    required TextStyle? style,
  }) {
    final spans = highlights.where((h) => h.field == field).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    if (spans.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final children = <InlineSpan>[];
    var lastEnd = 0;

    for (final span in spans) {
      final start = span.start.clamp(0, text.length);
      final end = span.end.clamp(0, text.length);
      if (start >= end || start < lastEnd) continue;

      if (start > lastEnd) {
        children.add(TextSpan(text: text.substring(lastEnd, start), style: style));
      }

      children.add(TextSpan(
        text: text.substring(start, end),
        style: style?.copyWith(
          backgroundColor: Colors.yellow.withValues(alpha: 0.35),
        ),
      ));
      lastEnd = end;
    }

    if (lastEnd < text.length) {
      children.add(TextSpan(text: text.substring(lastEnd), style: style));
    }

    return TextSpan(children: children);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCorrect = progress.isCorrect;
    final accentColor = isCorrect ? Colors.green : Colors.red;
    final explanationText = question.explanation.isEmpty
        ? 'No explanation was extracted for this item.'
        : question.explanation;

    return Card(
      color: accentColor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isCorrect ? Icons.check_circle : Icons.cancel,
                    color: accentColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isCorrect ? 'Correct' : 'Incorrect',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Correct answer: ${question.correctChoice}. ${question.correctChoiceText}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text.rich(
                _buildHighlightedSpan(
                  text: explanationText,
                  field: 'explanation',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (question.references.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'References',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                for (final reference in question.references)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(reference, style: theme.textTheme.bodySmall),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
