import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';

class AnswerRevealPanel extends StatelessWidget {
  const AnswerRevealPanel({
    required this.question,
    required this.progress,
    super.key,
  });

  final BookQuestion question;
  final QuestionProgress progress;

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
              Text(
                explanationText,
                style: theme.textTheme.bodyMedium,
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
