import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';

/// Bucket counts derived from a [StudyProgress] view of a question pool.
class _PoolBreakdown {
  const _PoolBreakdown({
    required this.correct,
    required this.incorrect,
    required this.answeredUnrevealed,
    required this.unanswered,
  });

  final int correct;
  final int incorrect;
  final int answeredUnrevealed;
  final int unanswered;

  int get total =>
      correct + incorrect + answeredUnrevealed + unanswered;

  int get answered => correct + incorrect + answeredUnrevealed;

  int get revealed => correct + incorrect;

  double get accuracy => revealed == 0 ? 0 : correct / revealed;

  static _PoolBreakdown forQuestions(
    Iterable<BookQuestion> questions,
    StudyProgress progress,
  ) {
    var correct = 0;
    var incorrect = 0;
    var answeredUnrevealed = 0;
    var unanswered = 0;
    for (final question in questions) {
      final qp = progress.answers[question.id];
      if (qp == null) {
        unanswered++;
        continue;
      }
      if (!qp.isRevealed) {
        answeredUnrevealed++;
        continue;
      }
      if (qp.isCorrect) {
        correct++;
      } else {
        incorrect++;
      }
    }
    return _PoolBreakdown(
      correct: correct,
      incorrect: incorrect,
      answeredUnrevealed: answeredUnrevealed,
      unanswered: unanswered,
    );
  }
}

class _ProgressPalette {
  const _ProgressPalette({
    required this.correct,
    required this.incorrect,
    required this.answeredUnrevealed,
    required this.unanswered,
  });

  final Color correct;
  final Color incorrect;
  final Color answeredUnrevealed;
  final Color unanswered;

  factory _ProgressPalette.from(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return _ProgressPalette(
      correct: isDark
          ? const Color(0xFF66BB6A)
          : const Color(0xFF2E7D32),
      incorrect: isDark
          ? const Color(0xFFEF5350)
          : const Color(0xFFC62828),
      answeredUnrevealed: scheme.primary,
      unanswered: scheme.onSurface.withValues(alpha: isDark ? 0.18 : 0.12),
    );
  }
}

/// Replaces the older sync-debug card on the library home with a visual
/// breakdown of the user's progress: an overall stacked bar (correct,
/// incorrect, answered-only, unanswered) plus per-book mini bars.
class ProgressOverviewCard extends StatelessWidget {
  const ProgressOverviewCard({
    required this.content,
    required this.progress,
    super.key,
  });

  final BookContent content;
  final StudyProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _ProgressPalette.from(theme.colorScheme, theme.brightness);
    final overall = _PoolBreakdown.forQuestions(content.questions, progress);
    final books = content.booksOrdered();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Progress overview',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _AccuracyBadge(
                  accuracy: overall.accuracy,
                  revealed: overall.revealed,
                  palette: palette,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _OverallStackedBar(
              breakdown: overall,
              palette: palette,
            ),
            const SizedBox(height: 12),
            _ProgressLegend(palette: palette),
            if (books.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(height: 1, color: theme.dividerColor),
              const SizedBox(height: 12),
              Text(
                'By book',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final book in books)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _BookProgressRow(
                    title: book.title,
                    breakdown: _PoolBreakdown.forQuestions(
                      content.questionsForBook(book.id),
                      progress,
                    ),
                    palette: palette,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OverallStackedBar extends StatelessWidget {
  const _OverallStackedBar({
    required this.breakdown,
    required this.palette,
  });

  final _PoolBreakdown breakdown;
  final _ProgressPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = breakdown.total;
    final answered = breakdown.answered;
    final answeredPct = total == 0 ? 0.0 : answered / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StackedBar(
          height: 18,
          breakdown: breakdown,
          palette: palette,
        ),
        const SizedBox(height: 8),
        Text(
          '$answered of $total answered '
          '(${(answeredPct * 100).toStringAsFixed(answeredPct == 1 ? 0 : 1)}%) '
          '— ${breakdown.correct} correct, '
          '${breakdown.incorrect} incorrect, '
          '${breakdown.unanswered} remaining',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BookProgressRow extends StatelessWidget {
  const _BookProgressRow({
    required this.title,
    required this.breakdown,
    required this.palette,
  });

  final String title;
  final _PoolBreakdown breakdown;
  final _ProgressPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = breakdown.total;
    final answered = breakdown.answered;
    final pct = total == 0 ? 0 : (answered / total * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$answered / $total · $pct%',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _StackedBar(
          height: 8,
          breakdown: breakdown,
          palette: palette,
        ),
      ],
    );
  }
}

class _StackedBar extends StatelessWidget {
  const _StackedBar({
    required this.height,
    required this.breakdown,
    required this.palette,
  });

  final double height;
  final _PoolBreakdown breakdown;
  final _ProgressPalette palette;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    final total = breakdown.total;
    if (total == 0) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: palette.unanswered,
          borderRadius: radius,
        ),
      );
    }
    final segments = <_BarSegment>[
      _BarSegment(value: breakdown.correct, color: palette.correct),
      _BarSegment(value: breakdown.incorrect, color: palette.incorrect),
      _BarSegment(
        value: breakdown.answeredUnrevealed,
        color: palette.answeredUnrevealed,
      ),
      _BarSegment(value: breakdown.unanswered, color: palette.unanswered),
    ];
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final seg in segments)
              if (seg.value > 0)
                Expanded(
                  flex: seg.value,
                  child: Container(color: seg.color),
                ),
          ],
        ),
      ),
    );
  }
}

class _BarSegment {
  const _BarSegment({required this.value, required this.color});
  final int value;
  final Color color;
}

class _ProgressLegend extends StatelessWidget {
  const _ProgressLegend({required this.palette});

  final _ProgressPalette palette;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _LegendDot(color: palette.correct, label: 'Correct'),
        _LegendDot(color: palette.incorrect, label: 'Incorrect'),
        _LegendDot(
          color: palette.answeredUnrevealed,
          label: 'Answered (not revealed)',
        ),
        _LegendDot(color: palette.unanswered, label: 'Remaining'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AccuracyBadge extends StatelessWidget {
  const _AccuracyBadge({
    required this.accuracy,
    required this.revealed,
    required this.palette,
  });

  final double accuracy;
  final int revealed;
  final _ProgressPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pctLabel = revealed == 0
        ? '—'
        : '${(accuracy * 100).toStringAsFixed(accuracy == 1 ? 0 : 1)}%';
    final ringColor = revealed == 0
        ? theme.colorScheme.surfaceContainerHighest
        : Color.lerp(palette.incorrect, palette.correct, accuracy.clamp(0, 1)) ??
            palette.correct;
    return Tooltip(
      message: revealed == 0
          ? 'No revealed answers yet'
          : 'Accuracy across $revealed revealed answers',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: ringColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ringColor, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 16, color: ringColor),
            const SizedBox(width: 6),
            Text(
              pctLabel,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: ringColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
