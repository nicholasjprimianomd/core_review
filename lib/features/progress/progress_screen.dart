import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import '../books/study_set_launcher.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({
    required this.content,
    required this.progressListenable,
    required this.themeMode,
    required this.onToggleTheme,
    required this.onOpenBook,
    required this.onStartStudySet,
    required this.onResetProgress,
    super.key,
  });

  final BookContent content;
  final ValueListenable<StudyProgress> progressListenable;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final ValueChanged<ReviewBook> onOpenBook;
  final StudySetLauncher onStartStudySet;
  final Future<void> Function() onResetProgress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
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
        builder: (context, progress, child) {
          final incorrectQuestions = content.questionsForIds(
            progress.incorrectQuestionIds,
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overall',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Answered: ${progress.answeredCount} / ${content.questions.length}',
                      ),
                      Text('Correct: ${progress.correctCount}'),
                      Text(
                        'Accuracy: ${(progress.accuracy * 100).toStringAsFixed(1)}%',
                      ),
                      if (progress.lastVisitedQuestionId != null) ...[
                        const SizedBox(height: 8),
                        Text('Last visited: ${progress.lastVisitedQuestionId}'),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: incorrectQuestions.isEmpty
                    ? null
                    : () => onStartStudySet(
                        'Review incorrect questions',
                        incorrectQuestions,
                      ),
                icon: const Icon(Icons.rule_folder),
                label: const Text('Review incorrect questions'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) {
                      return AlertDialog(
                        title: const Text('Reset progress?'),
                        content: const Text(
                          'This will clear your answered questions and accuracy history.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(dialogContext).pop(true),
                            child: const Text('Reset'),
                          ),
                        ],
                      );
                    },
                  );

                  if (confirmed != true) {
                    return;
                  }

                  await onResetProgress();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset progress'),
              ),
              const SizedBox(height: 24),
              Text(
                'By book',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (final book in content.booksOrdered())
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(book.title),
                    subtitle: Text(
                      _buildBookSummary(
                        content.questionsForBook(book.id),
                        progress,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onOpenBook(book),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _buildBookSummary(List<BookQuestion> questions, StudyProgress progress) {
  final answeredCount = questions
      .where((question) => progress.answers.containsKey(question.id))
      .length;
  final correctCount = questions
      .where((question) {
        final questionProgress = progress.answers[question.id];
        return questionProgress?.isRevealed == true &&
            (questionProgress?.isCorrect ?? false);
      })
      .length;
  return '$answeredCount of ${questions.length} answered, $correctCount correct';
}
