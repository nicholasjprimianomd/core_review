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
            if (question.isMatching)
              _MatchingAnswerKey(question: question, progress: progress)
            else
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
            ..._revealImageBlocks(theme, content, question),
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

class _MatchingAnswerKey extends StatelessWidget {
  const _MatchingAnswerKey({
    required this.question,
    required this.progress,
  });

  final BookQuestion question;
  final QuestionProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selections = progress.itemSelections ?? const <String, String>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Matching answers',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        for (final item in question.matchingItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _MatchingAnswerRow(
              question: question,
              item: item,
              submittedChoice: selections[item.label] ?? '',
            ),
          ),
      ],
    );
  }
}

class _MatchingAnswerRow extends StatelessWidget {
  const _MatchingAnswerRow({
    required this.question,
    required this.item,
    required this.submittedChoice,
  });

  final BookQuestion question;
  final MatchingItem item;
  final String submittedChoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final correctText = question.choices[item.correctChoice] ?? '';
    final isCorrect =
        submittedChoice.isNotEmpty && submittedChoice == item.correctChoice;
    final palette = isCorrect ? Colors.green : Colors.red;
    final submittedText = submittedChoice.isEmpty
        ? 'No answer'
        : '${question.choices[submittedChoice] ?? ''}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isCorrect ? Icons.check_circle_outline : Icons.cancel_outlined,
          size: 18,
          color: palette,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: '${item.label}: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: '${item.correctChoice}. $correctText'),
                if (submittedChoice.isNotEmpty &&
                    submittedChoice != item.correctChoice)
                  TextSpan(
                    text: '  (your answer: $submittedChoice. $submittedText)',
                    style: TextStyle(color: palette),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

List<Widget> _revealImageBlocks(
  ThemeData theme,
  BookContent content,
  BookQuestion question,
) {
  final stem = content.stemGroupImageAssetsMerged(question);
  final expOnly = content.explanationOnlyImageAssetsForStemGroup(question);
  final split = content.shouldSplitRevealImageSectionsForStemGroup(question);
  final headerStyle = theme.textTheme.titleSmall?.copyWith(
    fontWeight: FontWeight.w700,
  );
  if (split) {
    return [
      const SizedBox(height: 16),
      Text('Case images', style: headerStyle),
      const SizedBox(height: 8),
      BookImageGallery(imageAssets: stem),
      const SizedBox(height: 16),
      Text('Explanation figures', style: headerStyle),
      const SizedBox(height: 8),
      BookImageGallery(imageAssets: expOnly),
    ];
  }
  return [
    if (stem.isNotEmpty) ...[
      const SizedBox(height: 16),
      BookImageGallery(imageAssets: stem),
    ],
    if (expOnly.isNotEmpty) ...[
      const SizedBox(height: 16),
      BookImageGallery(imageAssets: expOnly),
    ],
  ];
}
