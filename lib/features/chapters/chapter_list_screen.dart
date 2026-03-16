import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import '../books/study_set_launcher.dart';

class ChapterListScreen extends StatelessWidget {
  const ChapterListScreen({
    required this.book,
    required this.content,
    required this.progressListenable,
    required this.themeMode,
    required this.onToggleTheme,
    required this.onOpenProgress,
    required this.onStartStudySet,
    super.key,
  });

  final ReviewBook book;
  final BookContent content;
  final ValueListenable<StudyProgress> progressListenable;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenProgress;
  final StudySetLauncher onStartStudySet;

  @override
  Widget build(BuildContext context) {
    final topics = content.topicsForBook(book.id);
    final bookQuestions = content.questionsForBook(book.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(book.title),
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
        ],
      ),
      body: ValueListenableBuilder<StudyProgress>(
        valueListenable: progressListenable,
        builder: (context, progress, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _BookSummaryBanner(
                book: book,
                questions: bookQuestions,
                progress: progress,
                onStartStudySet: () => onStartStudySet(book.title, bookQuestions),
              ),
              const SizedBox(height: 16),
              if (topics.isEmpty)
                for (final chapter in content.chaptersForBook(book.id))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _ChapterCard(
                      chapter: chapter,
                      questions: content.questionsForChapter(chapter.id),
                      progress: progress,
                      content: content,
                      onStartStudySet: onStartStudySet,
                    ),
                  )
              else
                for (final topic in topics)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _TopicCard(
                      topic: topic,
                      chapters: content.chaptersForTopic(topic.id),
                      content: content,
                      progress: progress,
                      onStartStudySet: onStartStudySet,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _BookSummaryBanner extends StatelessWidget {
  const _BookSummaryBanner({
    required this.book,
    required this.questions,
    required this.progress,
    required this.onStartStudySet,
  });

  final ReviewBook book;
  final List<BookQuestion> questions;
  final StudyProgress progress;
  final VoidCallback onStartStudySet;

  @override
  Widget build(BuildContext context) {
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
    final revealedCount = questions
        .where((question) => progress.answers[question.id]?.isRevealed ?? false)
        .length;
    final accuracy = revealedCount == 0 ? 0.0 : correctCount / revealedCount;

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
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricChip(
                  label: 'Answered',
                  value: '$answeredCount / ${questions.length}',
                ),
                _MetricChip(label: 'Correct', value: '$correctCount'),
                _MetricChip(
                  label: 'Accuracy',
                  value: '${(accuracy * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onStartStudySet,
              icon: const Icon(Icons.play_arrow_outlined),
              label: const Text('Study entire book'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.chapters,
    required this.content,
    required this.progress,
    required this.onStartStudySet,
  });

  final ReviewTopic topic;
  final List<BookChapter> chapters;
  final BookContent content;
  final StudyProgress progress;
  final StudySetLauncher onStartStudySet;

  @override
  Widget build(BuildContext context) {
    final topicQuestions = content.questionsForTopic(topic.id);
    final answeredCount = topicQuestions
        .where((question) => progress.answers.containsKey(question.id))
        .length;
    final correctCount = topicQuestions
        .where((question) {
          final questionProgress = progress.answers[question.id];
          return questionProgress?.isRevealed == true &&
              (questionProgress?.isCorrect ?? false);
        })
        .length;

    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          topic.title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '$answeredCount of ${topicQuestions.length} answered, $correctCount correct',
          ),
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onStartStudySet(topic.title, topicQuestions),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Study topic'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final chapter in chapters)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ChapterCard(
                chapter: chapter,
                questions: content.questionsForChapter(chapter.id),
                progress: progress,
                content: content,
                onStartStudySet: onStartStudySet,
              ),
            ),
        ],
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.chapter,
    required this.questions,
    required this.progress,
    required this.content,
    required this.onStartStudySet,
  });

  final BookChapter chapter;
  final List<BookQuestion> questions;
  final StudyProgress progress;
  final BookContent content;
  final StudySetLauncher onStartStudySet;

  @override
  Widget build(BuildContext context) {
    final answeredCount = _answeredCountFor(questions, progress);
    final correctCount = _correctCountFor(questions, progress);

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          chapter.displayTitle,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '$answeredCount of ${questions.length} answered, $correctCount correct',
          ),
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      onStartStudySet(chapter.displayTitle, questions),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Study chapter'),
                ),
              ),
            ],
          ),
          if (chapter.hasSections) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Subtopics',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            for (final section in chapter.sections)
              _SectionTile(
                section: section,
                questions: content.questionsForIds(section.questionIds),
                progress: progress,
                onTap: () => onStartStudySet(
                  '${chapter.displayTitle} - ${section.displayTitle}',
                  content.questionsForIds(section.questionIds),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.questions,
    required this.progress,
    required this.onTap,
  });

  final BookSection section;
  final List<BookQuestion> questions;
  final StudyProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final answeredCount = _answeredCountFor(questions, progress);
    final correctCount = _correctCountFor(questions, progress);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(section.displayTitle),
      subtitle: Text(
        '$answeredCount of ${questions.length} answered, $correctCount correct',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
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

int _answeredCountFor(List<BookQuestion> questions, StudyProgress progress) {
  return questions
      .where((question) => progress.answers.containsKey(question.id))
      .length;
}

int _correctCountFor(List<BookQuestion> questions, StudyProgress progress) {
  return questions
      .where((question) {
        final questionProgress = progress.answers[question.id];
        return questionProgress?.isRevealed == true &&
            (questionProgress?.isCorrect ?? false);
      })
      .length;
}
