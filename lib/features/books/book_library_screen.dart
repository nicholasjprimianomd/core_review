import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import 'study_set_launcher.dart';

class BookLibraryScreen extends StatelessWidget {
  const BookLibraryScreen({
    required this.content,
    required this.progressListenable,
    required this.themeMode,
    required this.currentUserEmail,
    required this.onToggleTheme,
    required this.onOpenAuth,
    required this.onOpenProgress,
    required this.onOpenBook,
    required this.onStartStudySet,
    super.key,
  });

  final BookContent content;
  final ValueListenable<StudyProgress> progressListenable;
  final ThemeMode themeMode;
  final String? currentUserEmail;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenAuth;
  final VoidCallback onOpenProgress;
  final ValueChanged<ReviewBook> onOpenBook;
  final StudySetLauncher onStartStudySet;

  @override
  Widget build(BuildContext context) {
    final books = content.booksOrdered();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Core Review'),
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
          IconButton(
            onPressed: onOpenProgress,
            tooltip: 'Progress',
            icon: const Icon(Icons.insights),
          ),
          IconButton(
            onPressed: onOpenAuth,
            tooltip: currentUserEmail == null
                ? 'Sign in'
                : 'Account: $currentUserEmail',
            icon: Icon(
              currentUserEmail == null ? Icons.login : Icons.account_circle,
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder<StudyProgress>(
        valueListenable: progressListenable,
        builder: (context, progress, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _OverallSummaryCard(
                answeredCount: progress.answeredCount,
                totalCount: content.questions.length,
                correctCount: progress.correctCount,
                currentUserEmail: currentUserEmail,
              ),
              const SizedBox(height: 16),
              for (final book in books)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _BookCard(
                    book: book,
                    topics: content.topicsForBook(book.id),
                    bookQuestions: content.questionsForBook(book.id),
                    progress: progress,
                    onOpenBook: () => onOpenBook(book),
                    onStartStudySet: () => onStartStudySet(
                      book.title,
                      content.questionsForBook(book.id),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OverallSummaryCard extends StatelessWidget {
  const _OverallSummaryCard({
    required this.answeredCount,
    required this.totalCount,
    required this.correctCount,
    required this.currentUserEmail,
  });

  final int answeredCount;
  final int totalCount;
  final int correctCount;
  final String? currentUserEmail;

  @override
  Widget build(BuildContext context) {
    final accuracy = answeredCount == 0 ? 0.0 : correctCount / answeredCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Library progress',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (currentUserEmail != null)
                  _MetricChip(label: 'Signed in', value: currentUserEmail!),
                _MetricChip(
                  label: 'Answered',
                  value: '$answeredCount / $totalCount',
                ),
                _MetricChip(label: 'Correct', value: '$correctCount'),
                _MetricChip(
                  label: 'Accuracy',
                  value: '${(accuracy * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.topics,
    required this.bookQuestions,
    required this.progress,
    required this.onOpenBook,
    required this.onStartStudySet,
  });

  final ReviewBook book;
  final List<ReviewTopic> topics;
  final List<BookQuestion> bookQuestions;
  final StudyProgress progress;
  final VoidCallback onOpenBook;
  final VoidCallback onStartStudySet;

  @override
  Widget build(BuildContext context) {
    final answeredCount = bookQuestions
        .where((question) => progress.answers.containsKey(question.id))
        .length;
    final correctCount = bookQuestions
        .where((question) {
          final questionProgress = progress.answers[question.id];
          return questionProgress?.isRevealed == true &&
              (questionProgress?.isCorrect ?? false);
        })
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              book.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '$answeredCount of ${bookQuestions.length} answered, $correctCount correct',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  label: 'Chapters',
                  value: '${book.chapterIds.length}',
                ),
              ],
            ),
            if (topics.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: topics
                    .map((topic) => Chip(label: Text(topic.title)))
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onOpenBook,
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Browse topics'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onStartStudySet,
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: const Text('Study all'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
