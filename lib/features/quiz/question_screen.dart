import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import '../../widgets/book_image_gallery.dart';
import '../assistant/assistant_repository.dart';
import '../assistant/question_assistant_sheet.dart';
import '../progress/progress_repository.dart';
import 'answer_reveal_panel.dart';
import 'question_controller.dart';

class QuestionScreen extends StatefulWidget {
  const QuestionScreen({
    required this.title,
    required this.content,
    required this.questions,
    required this.progressRepository,
    required this.initialProgress,
    required this.initialIndex,
    required this.themeMode,
    required this.onToggleTheme,
    required this.onProgressChanged,
    super.key,
  }) : assert(questions.length > 0, 'QuestionScreen requires at least 1 item.');

  final String title;
  final BookContent content;
  final List<BookQuestion> questions;
  final ProgressRepository progressRepository;
  final StudyProgress initialProgress;
  final int initialIndex;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final ValueChanged<StudyProgress> onProgressChanged;

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  double? _assistantPanelWidth;

  late final QuestionController _controller = QuestionController(
    questions: widget.questions,
    progressRepository: widget.progressRepository,
    initialProgress: widget.initialProgress,
    initialIndex: widget.initialIndex,
    onProgressChanged: widget.onProgressChanged,
  );
  late final AssistantRepository _assistantRepository = AssistantRepository();

  @override
  void dispose() {
    _assistantRepository.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final showQuestionNavigator = screenWidth >= 1200;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        final question = _controller.currentQuestion;
        final questionProgress = _controller.currentQuestionProgress;
        final selectedChoice = _controller.selectedChoice;
        final hasRevealedCurrentAnswer = _controller.hasRevealedCurrentAnswer;

        final navigatorPanel = _QuestionNavigatorPanel(
          title: widget.title,
          questions: _controller.questions,
          progress: _controller.progress,
          currentIndex: _controller.currentIndex,
          onSelectQuestion: (index) {
            if (!showQuestionNavigator) {
              Navigator.of(context).maybePop();
            }
            _controller.jumpToIndex(index);
          },
        );

        return Scaffold(
          key: _scaffoldKey,
          endDrawer: showQuestionNavigator
              ? null
              : Drawer(
                  width: 360,
                  child: SafeArea(child: navigatorPanel),
                ),
          appBar: AppBar(
            title: Text(widget.title),
            actions: [
              if (!showQuestionNavigator)
                IconButton(
                  onPressed: _openQuestionNavigator,
                  tooltip: 'Question list',
                  icon: const Icon(Icons.toc_outlined),
                ),
              IconButton(
                onPressed: _openAssistant,
                tooltip: 'Study assistant',
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Text(
                    '${_controller.currentIndex + 1}/${_controller.questionCount}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: _controller.completionFraction,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Chip(label: Text(question.bookTitle)),
                                  if (question.topicTitle != null)
                                    Chip(label: Text(question.topicTitle!)),
                                  Chip(
                                    label: Text(
                                      '${question.chapterNumber}. ${question.chapterTitle}',
                                    ),
                                  ),
                                  if (question.sectionTitle != null)
                                    Chip(label: Text(question.sectionTitle!)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Question ${question.displayNumber}',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              SelectionArea(
                                child: Text(
                                  question.prompt,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                              if (question.hasImages) ...[
                                const SizedBox(height: 20),
                                BookImageGallery(
                                  imageAssets: question.imageAssets,
                                ),
                              ],
                              const SizedBox(height: 20),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: _openAssistant,
                                    icon: const Icon(Icons.auto_awesome_outlined),
                                    label: const Text('Ask AI About This Question'),
                                  ),
                                  if (!showQuestionNavigator)
                                    OutlinedButton.icon(
                                      onPressed: _openQuestionNavigator,
                                      icon: const Icon(Icons.toc_outlined),
                                      label: const Text('Open Question List'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Choose your answer',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              for (final entry in question.choices.entries)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _ChoiceTile(
                                    optionLabel: entry.key,
                                    optionText: entry.value,
                                    isSelected: selectedChoice == entry.key,
                                    isCorrectAnswer:
                                        hasRevealedCurrentAnswer &&
                                        question.correctChoice == entry.key,
                                    isIncorrectSelection:
                                        hasRevealedCurrentAnswer &&
                                        questionProgress != null &&
                                        questionProgress.selectedChoice ==
                                            entry.key &&
                                        !questionProgress.isCorrect,
                                    enabled: questionProgress == null,
                                    onTap: () =>
                                        _controller.selectChoice(entry.key),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              if (_controller.shouldUseNextPartAction)
                                FilledButton.icon(
                                  onPressed: _controller.canAdvanceToNextPart
                                      ? _controller.submitCurrentPartAndAdvance
                                      : null,
                                  icon: _controller.isSaving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.chevron_right),
                                  label: const Text('Next Part'),
                                )
                              else
                                FilledButton.icon(
                                  onPressed: _controller.canSubmit
                                      ? _controller.submitCurrentAnswer
                                      : null,
                                  icon: _controller.isSaving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.visibility),
                                  label: const Text('Show Answer'),
                                ),
                              if (questionProgress != null &&
                                  !hasRevealedCurrentAnswer) ...[
                                const SizedBox(height: 16),
                                Text(
                                  'Answer saved. The shared explanation for this multipart set appears only on the final part.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                              if (questionProgress != null &&
                                  hasRevealedCurrentAnswer) ...[
                                const SizedBox(height: 16),
                                AnswerRevealPanel(
                                  question: question,
                                  progress: questionProgress,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _controller.canGoPrevious
                                      ? _controller.goToPrevious
                                      : null,
                                  icon: const Icon(Icons.chevron_left),
                                  label: const Text('Previous'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _controller.canGoNext
                                      ? _controller.goToNext
                                      : null,
                                  icon: const Icon(Icons.chevron_right),
                                  label: const Text('Next'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showQuestionNavigator) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(width: 340, child: navigatorPanel),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAssistant() async {
    final question = _controller.currentQuestion;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sheet = QuestionAssistantSheet(
      question: question,
      allowAnswerReveal: _controller.hasRevealedCurrentAnswer,
      assistantRepository: _assistantRepository,
    );

    if (screenWidth >= 780) {
      final defaultPanelWidth = screenWidth >= 1500
          ? 560.0
          : (screenWidth * 0.42).clamp(360.0, 560.0).toDouble();
      final minPanelWidth = 320.0;
      final maxPanelWidth = (screenWidth * 0.78).clamp(
        minPanelWidth,
        900.0,
      ).toDouble();
      final panelWidth = (_assistantPanelWidth ?? defaultPanelWidth)
          .clamp(minPanelWidth, maxPanelWidth)
          .toDouble();
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Close assistant',
        barrierColor: Colors.black.withValues(alpha: 0.2),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return SafeArea(
            child: _ResizableAssistantPanel(
              initialWidth: panelWidth,
              minWidth: minPanelWidth,
              maxWidth: maxPanelWidth,
              onWidthChanged: (width) {
                _assistantPanelWidth = width;
              },
              child: sheet,
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final offsetAnimation = Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(animation);
          return SlideTransition(position: offsetAnimation, child: child);
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return FractionallySizedBox(heightFactor: 0.94, child: sheet);
      },
    );
  }

  void _openQuestionNavigator() {
    _scaffoldKey.currentState?.openEndDrawer();
  }
}

class _ResizableAssistantPanel extends StatefulWidget {
  const _ResizableAssistantPanel({
    required this.child,
    required this.initialWidth,
    required this.minWidth,
    required this.maxWidth,
    required this.onWidthChanged,
  });

  final Widget child;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<double> onWidthChanged;

  @override
  State<_ResizableAssistantPanel> createState() =>
      _ResizableAssistantPanelState();
}

class _ResizableAssistantPanelState extends State<_ResizableAssistantPanel> {
  late double _width = widget.initialWidth;
  double? _dragStartWidth;
  double? _dragStartX;

  @override
  void didUpdateWidget(covariant _ResizableAssistantPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialWidth != widget.initialWidth && _dragStartWidth == null) {
      _width = widget.initialWidth;
    }
  }

  void _handleDragStart(DragStartDetails details) {
    _dragStartWidth = _width;
    _dragStartX = details.globalPosition.dx;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final dragStartWidth = _dragStartWidth;
    final dragStartX = _dragStartX;
    if (dragStartWidth == null || dragStartX == null) {
      return;
    }

    final delta = details.globalPosition.dx - dragStartX;
    final nextWidth = (dragStartWidth - delta)
        .clamp(widget.minWidth, widget.maxWidth)
        .toDouble();
    if ((nextWidth - _width).abs() < 1) {
      return;
    }

    setState(() {
      _width = nextWidth;
    });
    widget.onWidthChanged(nextWidth);
  }

  void _handleDragEnd([DragEndDetails? _]) {
    _dragStartWidth = null;
    _dragStartX = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: theme.scaffoldBackgroundColor,
        elevation: 12,
        child: SizedBox(
          width: _width,
          height: double.infinity,
          child: Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: _handleDragStart,
                  onHorizontalDragUpdate: _handleDragUpdate,
                  onHorizontalDragEnd: _handleDragEnd,
                  onHorizontalDragCancel: _handleDragEnd,
                  child: Tooltip(
                    message: 'Drag to resize',
                    child: SizedBox(
                      width: 20,
                      child: Center(
                        child: Container(
                          width: 4,
                          height: 84,
                          decoration: BoxDecoration(
                            color: theme.dividerColor.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: theme.dividerColor.withValues(alpha: 0.8),
              ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionNavigatorPanel extends StatelessWidget {
  const _QuestionNavigatorPanel({
    required this.title,
    required this.questions,
    required this.progress,
    required this.currentIndex,
    required this.onSelectQuestion,
  });

  final String title;
  final List<BookQuestion> questions;
  final StudyProgress progress;
  final int currentIndex;
  final ValueChanged<int> onSelectQuestion;

  @override
  Widget build(BuildContext context) {
    final groups = _buildQuestionGroups(questions);
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
    final incorrectCount = questions
        .where((question) {
          final questionProgress = progress.answers[question.id];
          return questionProgress?.isRevealed == true &&
              !(questionProgress?.isCorrect ?? true);
        })
        .length;

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Question Navigator',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _NavigatorStatChip(
                label: 'Answered',
                value: '$answeredCount/${questions.length}',
              ),
              _NavigatorStatChip(
                label: 'Correct',
                value: '$correctCount',
                color: Colors.green,
              ),
              _NavigatorStatChip(
                label: 'Incorrect',
                value: '$incorrectCount',
                color: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _QuestionGroupCard(
                group: group,
                progress: progress,
                currentIndex: currentIndex,
                onSelectQuestion: onSelectQuestion,
              ),
            ),
        ],
      ),
    );
  }
}

class _QuestionGroupCard extends StatelessWidget {
  const _QuestionGroupCard({
    required this.group,
    required this.progress,
    required this.currentIndex,
    required this.onSelectQuestion,
  });

  final _QuestionGroup group;
  final StudyProgress progress;
  final int currentIndex;
  final ValueChanged<int> onSelectQuestion;

  @override
  Widget build(BuildContext context) {
    final answeredCount = group.entries
        .where((entry) => progress.answers.containsKey(entry.question.id))
        .length;
    final correctCount = group.entries
        .where((entry) {
          final questionProgress = progress.answers[entry.question.id];
          return questionProgress?.isRevealed == true &&
              (questionProgress?.isCorrect ?? false);
        })
        .length;

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        key: PageStorageKey<String>('question-group-${group.id}'),
        initiallyExpanded: group.entries.any(
          (entry) => entry.index == currentIndex,
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Text(
          group.title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '$answeredCount of ${group.entries.length} answered, $correctCount correct',
          ),
        ),
        children: [
          for (final entry in group.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _QuestionNavigatorTile(
                entry: entry,
                isCurrent: entry.index == currentIndex,
                progress: progress.answers[entry.question.id],
                onTap: () => onSelectQuestion(entry.index),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuestionNavigatorTile extends StatelessWidget {
  const _QuestionNavigatorTile({
    required this.entry,
    required this.isCurrent,
    required this.progress,
    required this.onTap,
  });

  final _QuestionEntry entry;
  final bool isCurrent;
  final QuestionProgress? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _questionStatus(progress);
    final tileColor = isCurrent
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : null;
    final borderColor = isCurrent
        ? theme.colorScheme.primary
        : theme.dividerColor.withValues(alpha: 0.6);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          color: tileColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(status.icon, color: status.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Question ${entry.question.displayNumber}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: status.color,
                      ),
                    ),
                  ],
                ),
              ),
              if (progress != null)
                Text(
                  progress!.selectedChoice,
                  style: theme.textTheme.labelLarge,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigatorStatChip extends StatelessWidget {
  const _NavigatorStatChip({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: chipColor?.withValues(alpha: 0.12) ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionStatus {
  const _QuestionStatus({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

_QuestionStatus _questionStatus(QuestionProgress? progress) {
  if (progress == null) {
    return const _QuestionStatus(
      label: 'Unanswered',
      icon: Icons.radio_button_unchecked,
      color: Colors.grey,
    );
  }

  if (!progress.isRevealed) {
    return const _QuestionStatus(
      label: 'Answered',
      icon: Icons.check_circle_outline,
      color: Colors.blueGrey,
    );
  }

  if (progress.isCorrect) {
    return const _QuestionStatus(
      label: 'Correct',
      icon: Icons.check_circle,
      color: Colors.green,
    );
  }

  return const _QuestionStatus(
    label: 'Incorrect',
    icon: Icons.cancel,
    color: Colors.red,
  );
}

List<_QuestionGroup> _buildQuestionGroups(List<BookQuestion> questions) {
  final groups = <_QuestionGroup>[];

  for (var index = 0; index < questions.length; index++) {
    final question = questions[index];
    final groupId = '${question.chapterId}::${question.sectionId ?? ''}';
    final groupTitle = question.sectionTitle != null
        ? '${question.chapterNumber}. ${question.chapterTitle} - ${question.sectionTitle}'
        : '${question.chapterNumber}. ${question.chapterTitle}';

    if (groups.isEmpty || groups.last.id != groupId) {
      groups.add(
        _QuestionGroup(
          id: groupId,
          title: groupTitle,
          entries: <_QuestionEntry>[],
        ),
      );
    }

    groups.last.entries.add(
      _QuestionEntry(index: index, question: question),
    );
  }

  return groups;
}

class _QuestionGroup {
  _QuestionGroup({
    required this.id,
    required this.title,
    required this.entries,
  });

  final String id;
  final String title;
  final List<_QuestionEntry> entries;
}

class _QuestionEntry {
  const _QuestionEntry({
    required this.index,
    required this.question,
  });

  final int index;
  final BookQuestion question;
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.optionLabel,
    required this.optionText,
    required this.isSelected,
    required this.isCorrectAnswer,
    required this.isIncorrectSelection,
    required this.enabled,
    required this.onTap,
  });

  final String optionLabel;
  final String optionText;
  final bool isSelected;
  final bool isCorrectAnswer;
  final bool isIncorrectSelection;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? borderColor;
    Color? backgroundColor;

    if (isCorrectAnswer) {
      borderColor = Colors.green;
      backgroundColor = Colors.green.withValues(alpha: 0.08);
    } else if (isIncorrectSelection) {
      borderColor = Colors.red;
      backgroundColor = Colors.red.withValues(alpha: 0.08);
    } else if (isSelected) {
      borderColor = theme.colorScheme.primary;
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.08);
    }

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor ?? theme.dividerColor,
            width: borderColor == null ? 1 : 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 16, child: Text(optionLabel)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(optionText, style: theme.textTheme.bodyLarge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
