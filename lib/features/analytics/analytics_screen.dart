import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({
    required this.content,
    required this.progressListenable,
    required this.themeMode,
    required this.onToggleTheme,
    super.key,
  });

  final BookContent content;
  final ValueListenable<StudyProgress> progressListenable;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Analytics'),
        actions: [
          IconButton(
            onPressed: onToggleTheme,
            tooltip: themeMode == ThemeMode.dark
                ? 'Switch to light mode'
                : 'Switch to dark mode',
            icon: Icon(
              themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder<StudyProgress>(
        valueListenable: progressListenable,
        builder: (context, progress, _) {
          if (progress.answeredCount == 0) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No data yet. Answer some questions to see your analytics.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _OverallStatsCard(content: content, progress: progress),
              const SizedBox(height: 16),
              _AccuracyByBookCard(content: content, progress: progress),
              const SizedBox(height: 16),
              _AccuracyByChapterCard(content: content, progress: progress),
              const SizedBox(height: 16),
              _RecentActivityCard(progress: progress),
            ],
          );
        },
      ),
    );
  }
}

class _OverallStatsCard extends StatelessWidget {
  const _OverallStatsCard({required this.content, required this.progress});

  final BookContent content;
  final StudyProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = content.questions.length;
    final answered = progress.answeredCount;
    final revealed = progress.revealedCount;
    final correct = progress.correctCount;
    final incorrect = revealed - correct;
    final accuracy = progress.accuracy;
    final completion = total == 0 ? 0.0 : answered / total;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overall Performance',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _CircularStat(
                    label: 'Accuracy',
                    value: accuracy,
                    color: _accuracyColor(accuracy),
                    displayText: '${(accuracy * 100).toStringAsFixed(1)}%',
                  ),
                ),
                Expanded(
                  child: _CircularStat(
                    label: 'Completion',
                    value: completion,
                    color: Colors.blue,
                    displayText: '${(completion * 100).toStringAsFixed(1)}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatChip(label: 'Answered', value: '$answered', color: Colors.blue),
                _StatChip(label: 'Correct', value: '$correct', color: Colors.green),
                _StatChip(label: 'Incorrect', value: '$incorrect', color: Colors.red),
                _StatChip(label: 'Remaining', value: '${total - answered}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccuracyByBookCard extends StatelessWidget {
  const _AccuracyByBookCard({required this.content, required this.progress});

  final BookContent content;
  final StudyProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = content.booksOrdered();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Accuracy by Book',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            for (final book in books) ...[
              _buildBookBar(context, book),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBookBar(BuildContext context, ReviewBook book) {
    final theme = Theme.of(context);
    final questions = content.questionsForBook(book.id);
    final stats = _computeStats(questions, progress);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                book.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              stats.revealed == 0
                  ? 'No data'
                  : '${(stats.accuracy * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: stats.revealed == 0
                    ? theme.hintColor
                    : _accuracyColor(stats.accuracy),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _AccuracyBar(stats: stats, total: questions.length),
        const SizedBox(height: 2),
        Text(
          '${stats.answered} of ${questions.length} answered',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
    );
  }
}

class _AccuracyByChapterCard extends StatelessWidget {
  const _AccuracyByChapterCard({
    required this.content,
    required this.progress,
  });

  final BookContent content;
  final StudyProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final chapterStats = <({BookChapter chapter, _ChapterStats stats})>[];
    for (final book in content.booksOrdered()) {
      for (final chapter in content.chaptersForBook(book.id)) {
        final questions = content.questionsForChapter(chapter.id);
        final stats = _computeStats(questions, progress);
        if (stats.answered > 0) {
          chapterStats.add((chapter: chapter, stats: stats));
        }
      }
    }

    if (chapterStats.isEmpty) {
      return const SizedBox.shrink();
    }

    chapterStats.sort((a, b) => a.stats.accuracy.compareTo(b.stats.accuracy));

    final weakest = chapterStats.take(5).toList();
    final strongest = chapterStats.reversed.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chapter Breakdown',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            if (weakest.isNotEmpty) ...[
              Text(
                'Weakest areas',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade300,
                ),
              ),
              const SizedBox(height: 8),
              for (final entry in weakest)
                _ChapterStatRow(
                  chapter: entry.chapter,
                  stats: entry.stats,
                ),
            ],
            const SizedBox(height: 16),
            if (strongest.isNotEmpty) ...[
              Text(
                'Strongest areas',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade300,
                ),
              ),
              const SizedBox(height: 8),
              for (final entry in strongest)
                _ChapterStatRow(
                  chapter: entry.chapter,
                  stats: entry.stats,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.progress});

  final StudyProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final entries = progress.answers.entries.toList()
      ..sort((a, b) => b.value.answeredAt.compareTo(a.value.answeredAt));

    final byDay = <String, _DayStats>{};
    for (final entry in entries) {
      final date = _dateKey(entry.value.answeredAt);
      final stats = byDay.putIfAbsent(date, () => _DayStats());
      stats.total++;
      if (entry.value.isRevealed && entry.value.isCorrect) {
        stats.correct++;
      }
      if (entry.value.isRevealed && !entry.value.isCorrect) {
        stats.incorrect++;
      }
    }

    final sortedDays = byDay.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final recentDays = sortedDays.take(14).toList();

    if (recentDays.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Activity',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            for (final day in recentDays)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ActivityDayRow(dateKey: day.key, stats: day.value),
              ),
          ],
        ),
      ),
    );
  }

  static String _dateKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _CircularStat extends StatelessWidget {
  const _CircularStat({
    required this.label,
    required this.value,
    required this.color,
    required this.displayText,
  });

  final String label;
  final double value;
  final Color color;
  final String displayText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  value: value.clamp(0, 1),
                  strokeWidth: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
              Text(
                displayText,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (color ?? theme.colorScheme.primary).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AccuracyBar extends StatelessWidget {
  const _AccuracyBar({required this.stats, required this.total});

  final _ChapterStats stats;
  final int total;

  @override
  Widget build(BuildContext context) {
    final correctFrac = total == 0 ? 0.0 : stats.correct / total;
    final incorrectFrac = total == 0 ? 0.0 : (stats.revealed - stats.correct) / total;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            if (correctFrac > 0)
              Expanded(
                flex: (correctFrac * 1000).round(),
                child: Container(color: Colors.green),
              ),
            if (incorrectFrac > 0)
              Expanded(
                flex: (incorrectFrac * 1000).round(),
                child: Container(color: Colors.red.shade300),
              ),
            Expanded(
              flex: math.max(0, (1000 - (correctFrac * 1000).round() - (incorrectFrac * 1000).round())),
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterStatRow extends StatelessWidget {
  const _ChapterStatRow({required this.chapter, required this.stats});

  final BookChapter chapter;
  final _ChapterStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              chapter.displayTitle,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              stats.revealed == 0
                  ? '--'
                  : '${(stats.accuracy * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: _accuracyColor(stats.accuracy),
              ),
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${stats.correct}/${stats.revealed}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}

class _ActivityDayRow extends StatelessWidget {
  const _ActivityDayRow({required this.dateKey, required this.stats});

  final String dateKey;
  final _DayStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accuracy = stats.total == 0 ? 0.0 : stats.correct / stats.total;
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(dateKey, style: theme.textTheme.bodySmall),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: accuracy.clamp(0, 1),
              minHeight: 8,
              color: _accuracyColor(accuracy),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(
            '${stats.total} Q, ${(accuracy * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _ChapterStats {
  int answered = 0;
  int revealed = 0;
  int correct = 0;

  double get accuracy => revealed == 0 ? 0 : correct / revealed;
}

class _DayStats {
  int total = 0;
  int correct = 0;
  int incorrect = 0;
}

_ChapterStats _computeStats(
  List<BookQuestion> questions,
  StudyProgress progress,
) {
  final stats = _ChapterStats();
  for (final q in questions) {
    final p = progress.answers[q.id];
    if (p != null) {
      stats.answered++;
      if (p.isRevealed) {
        stats.revealed++;
        if (p.isCorrect) stats.correct++;
      }
    }
  }
  return stats;
}

Color _accuracyColor(double accuracy) {
  if (accuracy >= 0.8) return Colors.green;
  if (accuracy >= 0.6) return Colors.orange;
  return Colors.red;
}
