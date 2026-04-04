import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import '../../models/text_highlight_utils.dart';
import '../../widgets/book_image_gallery.dart';
import '../../widgets/formatted_explanation_select.dart';

class AnswerRevealPanel extends StatelessWidget {
  const AnswerRevealPanel({
    required this.content,
    required this.question,
    required this.progress,
    required this.explanationHighlights,
    required this.onExplanationHighlightsChanged,
    super.key,
  });

  final BookContent content;
  final BookQuestion question;
  final QuestionProgress progress;
  final List<TextHighlightSpan> explanationHighlights;
  final ValueChanged<List<TextHighlightSpan>> onExplanationHighlightsChanged;

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
            FormattedExplanationSelect(
              fullText: explanationText,
              baseStyle: theme.textTheme.bodyLarge,
              headerStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              highlights: explanationHighlights,
              onHighlightsChanged: onExplanationHighlightsChanged,
            ),
            if (content.revealImageAssetsOrderedForStemGroup(question).isNotEmpty) ...[
              const SizedBox(height: 16),
              if (content.shouldSplitRevealImageSectionsForStemGroup(question)) ...[
                Text(
                  'Case images',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                BookImageGallery(
                  imageAssets: content.stemGroupImageAssetsMerged(question),
                ),
                const SizedBox(height: 16),
                Text(
                  'Explanation figures',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                BookImageGallery(
                  imageAssets:
                      content.explanationOnlyImageAssetsForStemGroup(question),
                ),
              ] else
                BookImageGallery(
                  imageAssets:
                      content.revealImageAssetsOrderedForStemGroup(question),
                ),
            ],
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
                  child: Text(reference, style: theme.textTheme.bodyMedium),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
