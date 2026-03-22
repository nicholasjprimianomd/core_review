import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import 'exam_pool_builder.dart';
import 'exam_session_models.dart';

typedef ExamLaunchCallback = void Function(ExamLaunchRequest request);

class CustomExamSetupScreen extends StatefulWidget {
  const CustomExamSetupScreen({
    required this.content,
    required this.progressListenable,
    required this.themeMode,
    required this.onToggleTheme,
    required this.onLaunch,
    super.key,
  });

  final BookContent content;
  final ValueListenable<StudyProgress> progressListenable;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final ExamLaunchCallback onLaunch;

  @override
  State<CustomExamSetupScreen> createState() => _CustomExamSetupScreenState();
}

class _CustomExamSetupScreenState extends State<CustomExamSetupScreen> {
  final Set<String> _bookIds = {};
  final Set<String> _chapterIds = {};
  final Set<String> _sectionIds = {};

  final TextEditingController _countController = TextEditingController(text: '20');
  final TextEditingController _minutesController = TextEditingController(
    text: '45',
  );

  CompletionFilter _completionFilter = CompletionFilter.allPool;
  ExamMode _examMode = ExamMode.test;
  bool _noTimeLimit = true;

  @override
  void dispose() {
    _countController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  ExamScopeSelection get _scope => ExamScopeSelection(
    bookIds: Set<String>.unmodifiable(_bookIds),
    chapterIds: Set<String>.unmodifiable(_chapterIds),
    sectionIds: Set<String>.unmodifiable(_sectionIds),
  );

  void _toggleBook(String bookId, bool? selected) {
    setState(() {
      if (selected ?? false) {
        _bookIds.add(bookId);
      } else {
        _bookIds.remove(bookId);
      }
    });
  }

  void _toggleChapter(String chapterId, bool? selected) {
    setState(() {
      if (selected ?? false) {
        _chapterIds.add(chapterId);
      } else {
        _chapterIds.remove(chapterId);
      }
    });
  }

  void _toggleSection(String sectionId, bool? selected) {
    setState(() {
      if (selected ?? false) {
        _sectionIds.add(sectionId);
      } else {
        _sectionIds.remove(sectionId);
      }
    });
  }

  void _startExam(StudyProgress progress) {
    final parsed = int.tryParse(_countController.text.trim());
    if (parsed == null || parsed < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid number of questions (at least 1).')),
      );
      return;
    }

    if (_scope.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one book, chapter, or section.')),
      );
      return;
    }

    final maxAvail = maxQuestionsAvailableForExam(
      content: widget.content,
      selection: _scope,
      completionFilter: _completionFilter,
      progress: progress,
    );

    if (maxAvail < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No questions match this scope and filter. Try changing the filter or scope.'),
        ),
      );
      return;
    }

    final desired = parsed > maxAvail ? maxAvail : parsed;

    Duration? timeLimit;
    if (!_noTimeLimit) {
      final minutes = int.tryParse(_minutesController.text.trim());
      if (minutes == null || minutes < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a time limit of at least 1 minute.')),
        );
        return;
      }
      timeLimit = Duration(minutes: minutes);
    }

    final questions = buildExamQuestionList(
      content: widget.content,
      selection: _scope,
      completionFilter: _completionFilter,
      progress: progress,
      questionCount: desired,
      random: Random(),
    );

    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not build an exam from the current settings.')),
      );
      return;
    }

    final modeLabel = _examMode == ExamMode.test ? 'Test' : 'Tutor';
    final title = 'Custom exam · $modeLabel · ${questions.length} Q';

    widget.onLaunch(
      ExamLaunchRequest(
        title: title,
        questions: questions,
        options: ExamSessionOptions(
          mode: _examMode,
          title: title,
          timeLimit: timeLimit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom exam'),
        actions: [
          IconButton(
            onPressed: widget.onToggleTheme,
            tooltip: widget.themeMode == ThemeMode.dark
                ? 'Switch to light mode'
                : 'Switch to dark mode',
            icon: Icon(
              widget.themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder<StudyProgress>(
        valueListenable: widget.progressListenable,
        builder: (context, progress, _) {
          final maxAvail = _scope.isEmpty
              ? 0
              : maxQuestionsAvailableForExam(
                  content: widget.content,
                  selection: _scope,
                  completionFilter: _completionFilter,
                  progress: progress,
                );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Scope',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose books, chapters, or sections. Selections are combined.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (final book in widget.content.booksOrdered())
                _BookScopeTile(
                  book: book,
                  content: widget.content,
                  bookSelected: _bookIds.contains(book.id),
                  chapterSelection: _chapterIds,
                  sectionSelection: _sectionIds,
                  onBookChanged: _toggleBook,
                  onChapterChanged: _toggleChapter,
                  onSectionChanged: _toggleSection,
                ),
              const SizedBox(height: 24),
              Text(
                'Question count',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _countController,
                decoration: const InputDecoration(
                  labelText: 'Number of questions',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              if (maxAvail > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Up to $maxAvail questions match scope and filter (multipart sets count as full stems).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Completion filter',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<CompletionFilter>(
                value: _completionFilter,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                    value: CompletionFilter.allPool,
                    child: Text('All pool'),
                  ),
                  DropdownMenuItem(
                    value: CompletionFilter.unansweredOnly,
                    child: Text('Unanswered only'),
                  ),
                  DropdownMenuItem(
                    value: CompletionFilter.incorrectOnly,
                    child: Text('Incorrect only'),
                  ),
                  DropdownMenuItem(
                    value: CompletionFilter.answeredOnly,
                    child: Text('Answered only'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _completionFilter = v);
                  }
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Mode',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SegmentedButton<ExamMode>(
                segments: const [
                  ButtonSegment(value: ExamMode.test, label: Text('Test')),
                  ButtonSegment(value: ExamMode.tutor, label: Text('Tutor')),
                ],
                selected: {_examMode},
                onSelectionChanged: (s) {
                  if (s.isEmpty) {
                    return;
                  }
                  setState(() => _examMode = s.first);
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Test: hide explanations and scores until you end the block. Tutor: immediate feedback like normal study.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Text(
                'Time limit',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('No time limit'),
                value: _noTimeLimit,
                onChanged: (v) => setState(() => _noTimeLimit = v),
              ),
              if (!_noTimeLimit) ...[
                TextField(
                  controller: _minutesController,
                  decoration: const InputDecoration(
                    labelText: 'Minutes',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => _startExam(progress),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start exam'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BookScopeTile extends StatelessWidget {
  const _BookScopeTile({
    required this.book,
    required this.content,
    required this.bookSelected,
    required this.chapterSelection,
    required this.sectionSelection,
    required this.onBookChanged,
    required this.onChapterChanged,
    required this.onSectionChanged,
  });

  final ReviewBook book;
  final BookContent content;
  final bool bookSelected;
  final Set<String> chapterSelection;
  final Set<String> sectionSelection;
  final void Function(String bookId, bool? selected) onBookChanged;
  final void Function(String chapterId, bool? selected) onChapterChanged;
  final void Function(String sectionId, bool? selected) onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final topics = content.topicsForBook(book.id);
    final chapters = topics.isEmpty
        ? content.chaptersForBook(book.id)
        : <BookChapter>[];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        leading: Checkbox(
          value: bookSelected,
          onChanged: (v) => onBookChanged(book.id, v),
        ),
        title: Text(book.title),
        subtitle: const Text('Whole book'),
        children: [
          if (topics.isNotEmpty)
            for (final topic in topics)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: _TopicScopeSection(
                  topic: topic,
                  content: content,
                  chapterSelection: chapterSelection,
                  sectionSelection: sectionSelection,
                  onChapterChanged: onChapterChanged,
                  onSectionChanged: onSectionChanged,
                ),
              )
          else
            for (final chapter in chapters)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: _ChapterScopeTile(
                  chapter: chapter,
                  chapterSelected: chapterSelection.contains(chapter.id),
                  sectionSelection: sectionSelection,
                  onChapterChanged: onChapterChanged,
                  onSectionChanged: onSectionChanged,
                ),
              ),
        ],
      ),
    );
  }
}

class _TopicScopeSection extends StatelessWidget {
  const _TopicScopeSection({
    required this.topic,
    required this.content,
    required this.chapterSelection,
    required this.sectionSelection,
    required this.onChapterChanged,
    required this.onSectionChanged,
  });

  final ReviewTopic topic;
  final BookContent content;
  final Set<String> chapterSelection;
  final Set<String> sectionSelection;
  final void Function(String chapterId, bool? selected) onChapterChanged;
  final void Function(String sectionId, bool? selected) onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final chapters = content.chaptersForTopic(topic.id);
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        title: Text(topic.title),
        children: [
            for (final chapter in chapters)
              _ChapterScopeTile(
                chapter: chapter,
                chapterSelected: chapterSelection.contains(chapter.id),
                sectionSelection: sectionSelection,
                onChapterChanged: onChapterChanged,
                onSectionChanged: onSectionChanged,
              ),
        ],
      ),
    );
  }
}

class _ChapterScopeTile extends StatelessWidget {
  const _ChapterScopeTile({
    required this.chapter,
    required this.chapterSelected,
    required this.sectionSelection,
    required this.onChapterChanged,
    required this.onSectionChanged,
  });

  final BookChapter chapter;
  final bool chapterSelected;
  final Set<String> sectionSelection;
  final void Function(String chapterId, bool? selected) onChapterChanged;
  final void Function(String sectionId, bool? selected) onSectionChanged;

  @override
  Widget build(BuildContext context) {
    if (!chapter.hasSections) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: CheckboxListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          value: chapterSelected,
          onChanged: (v) => onChapterChanged(chapter.id, v),
          title: Text(chapter.displayTitle),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        leading: Checkbox(
          value: chapterSelected,
          onChanged: (v) => onChapterChanged(chapter.id, v),
        ),
        title: Text(chapter.displayTitle),
        subtitle: const Text('Whole chapter'),
        children: [
          for (final section in chapter.sections)
            CheckboxListTile(
              value: sectionSelection.contains(section.id),
              onChanged: (v) => onSectionChanged(section.id, v),
              title: Text(section.displayTitle),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
        ],
      ),
    );
  }
}
