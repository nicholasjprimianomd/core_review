import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import '../../models/study_data_models.dart';
import '../../widgets/book_image_gallery.dart';
import '../assistant/assistant_repository.dart';
import '../assistant/question_assistant_sheet.dart';
import '../exam/exam_session_models.dart';
import '../exam/exam_summary_screen.dart';
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
    required this.initialStudyData,
    required this.initialIndex,
    required this.themeMode,
    required this.onToggleTheme,
    required this.onProgressChanged,
    required this.onStudyDataChanged,
    this.examSession,
    super.key,
  }) : assert(questions.length > 0, 'QuestionScreen requires at least 1 item.');

  final String title;
  final BookContent content;
  final List<BookQuestion> questions;
  final ProgressRepository progressRepository;
  final StudyProgress initialProgress;
  final StudyData initialStudyData;
  final int initialIndex;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final ValueChanged<StudyProgress> onProgressChanged;
  final ValueChanged<StudyData> onStudyDataChanged;
  final ExamSessionOptions? examSession;

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  double? _assistantPanelWidth;
  Timer? _examTicker;
  late final DateTime _examStartedAt;
  bool _examSummaryRouteOpen = false;

  late final QuestionController _controller = QuestionController(
    questions: widget.questions,
    progressRepository: widget.progressRepository,
    initialProgress: widget.initialProgress,
    initialIndex: widget.initialIndex,
    onProgressChanged: widget.onProgressChanged,
    deferRevealUntilExamEnd: widget.examSession?.deferRevealUntilEnd ?? false,
  );
  late final AssistantRepository _assistantRepository = AssistantRepository();
  late StudyData _studyData = widget.initialStudyData;

  QuestionStudyData get _currentStudyData =>
      _studyData.forQuestion(_controller.currentQuestion.id);

  void _updateStudyData(QuestionStudyData data) {
    setState(() {
      _studyData = _studyData.withQuestion(
        _controller.currentQuestion.id,
        data,
      );
    });
    widget.onStudyDataChanged(_studyData);
  }

  void _toggleFlag() {
    final current = _currentStudyData;
    _updateStudyData(current.copyWith(isFlagged: !current.isFlagged));
  }

  @override
  void initState() {
    super.initState();
    _examStartedAt = DateTime.now();
    final limit = widget.examSession?.timeLimit;
    if (limit != null) {
      _examTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        setState(() {});
        final elapsed = DateTime.now().difference(_examStartedAt);
        if (elapsed >= limit) {
          _examTicker?.cancel();
          _examTicker = null;
          unawaited(_endExamSession(timeUp: true));
        }
      });
    }
  }

  @override
  void dispose() {
    _examTicker?.cancel();
    _assistantRepository.dispose();
    _controller.dispose();
    super.dispose();
  }

  Duration? get _examTimeRemaining {
    final limit = widget.examSession?.timeLimit;
    if (limit == null) {
      return null;
    }
    final left = limit - DateTime.now().difference(_examStartedAt);
    if (left <= Duration.zero) {
      return Duration.zero;
    }
    return left;
  }

  Future<void> _endExamSession({bool timeUp = false}) async {
    final exam = widget.examSession;
    if (exam == null || _examSummaryRouteOpen || !mounted) {
      return;
    }

    if (!timeUp) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('End block'),
                content: const Text(
                  'End this exam block and view your summary?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('End block'),
                  ),
                ],
              );
            },
          ) ??
          false;
      if (!confirmed || !mounted) {
        return;
      }
    }

    if (exam.deferRevealUntilEnd) {
      await _controller.finishDeferredExamReveals();
    }
    if (!mounted) {
      return;
    }

    _examSummaryRouteOpen = true;
    final endedAt = DateTime.now();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ExamSummaryScreen(
          title: widget.title,
          questions: widget.questions,
          progress: _controller.progress,
          startedAt: _examStartedAt,
          endedAt: endedAt,
          examMode: exam.mode,
          timeLimit: exam.timeLimit,
        ),
      ),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
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
        final explanationsVisible =
            _controller.explanationsVisibleForCurrent;
        final examDefer = widget.examSession?.deferRevealUntilEnd == true;

        final currentStudyData = _currentStudyData;

        final navigatorPanel = _QuestionNavigatorPanel(
          title: widget.title,
          questions: _controller.questions,
          progress: _controller.progress,
          studyData: _studyData,
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
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_examTimeRemaining != null)
                  Text(
                    'Time left ${_formatCountdown(_examTimeRemaining!)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
            actions: [
              if (widget.examSession != null)
                IconButton(
                  onPressed: _controller.isSaving ? null : () => _endExamSession(),
                  tooltip: 'End block',
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              IconButton(
                onPressed: _toggleFlag,
                tooltip: currentStudyData.isFlagged ? 'Unflag question' : 'Flag question',
                icon: Icon(
                  currentStudyData.isFlagged ? Icons.flag : Icons.flag_outlined,
                  color: currentStudyData.isFlagged ? Colors.orange : null,
                ),
              ),
              IconButton(
                onPressed: () => _openNotes(question),
                tooltip: currentStudyData.hasNote ? 'Edit note' : 'Add note',
                icon: Icon(
                  currentStudyData.hasNote
                      ? Icons.sticky_note_2
                      : Icons.sticky_note_2_outlined,
                  color: currentStudyData.hasNote ? Colors.amber : null,
                ),
              ),
              IconButton(
                onPressed: () => _openHighlightDialog(question, currentStudyData),
                tooltip: currentStudyData.hasHighlights
                    ? 'Manage highlights (${currentStudyData.highlights.length})'
                    : 'Add highlight',
                icon: Icon(
                  Icons.highlight,
                  color: currentStudyData.hasHighlights ? Colors.yellow.shade700 : null,
                ),
              ),
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
                              _HighlightableText(
                                text: question.prompt,
                                field: 'prompt',
                                highlights: currentStudyData.highlights,
                                style: Theme.of(context).textTheme.bodyLarge,
                                onHighlight: (span) {
                                  final updated = List<HighlightSpan>.from(
                                    currentStudyData.highlights,
                                  )..add(span);
                                  _updateStudyData(
                                    currentStudyData.copyWith(highlights: updated),
                                  );
                                },
                                onRemoveHighlight: (span) {
                                  final updated = List<HighlightSpan>.from(
                                    currentStudyData.highlights,
                                  )..removeWhere(
                                    (h) =>
                                        h.field == span.field &&
                                        h.start == span.start &&
                                        h.end == span.end,
                                  );
                                  _updateStudyData(
                                    currentStudyData.copyWith(highlights: updated),
                                  );
                                },
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
                                    isCorrectAnswer: hasRevealedCurrentAnswer &&
                                        explanationsVisible &&
                                        question.correctChoice == entry.key,
                                    isIncorrectSelection: hasRevealedCurrentAnswer &&
                                        explanationsVisible &&
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
                                      : Icon(
                                          examDefer
                                              ? Icons.check_circle_outline
                                              : Icons.visibility,
                                        ),
                                  label: Text(
                                    examDefer ? 'Save answer' : 'Show Answer',
                                  ),
                                ),
                              if (questionProgress != null &&
                                  !hasRevealedCurrentAnswer) ...[
                                const SizedBox(height: 16),
                                Text(
                                  examDefer
                                      ? 'Answer saved. Explanations and scores stay hidden until you end the block.'
                                      : 'Answer saved. The shared explanation for this multipart set appears only on the final part.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                              if (currentStudyData.hasNote) ...[
                                const SizedBox(height: 16),
                                _NoteCard(
                                  note: currentStudyData.note,
                                  onEdit: () => _openNotes(question),
                                ),
                              ],
                              if (questionProgress != null &&
                                  explanationsVisible) ...[
                                const SizedBox(height: 16),
                                AnswerRevealPanel(
                                  question: question,
                                  progress: questionProgress,
                                  highlights: currentStudyData.highlights,
                                  onHighlight: (span) {
                                    final updated = List<HighlightSpan>.from(
                                      currentStudyData.highlights,
                                    )..add(span);
                                    _updateStudyData(
                                      currentStudyData.copyWith(highlights: updated),
                                    );
                                  },
                                  onRemoveHighlight: (span) {
                                    final updated = List<HighlightSpan>.from(
                                      currentStudyData.highlights,
                                    )..removeWhere(
                                      (h) =>
                                          h.field == span.field &&
                                          h.start == span.start &&
                                          h.end == span.end,
                                    );
                                    _updateStudyData(
                                      currentStudyData.copyWith(highlights: updated),
                                    );
                                  },
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

  static String _formatCountdown(Duration d) {
    final total = d.inSeconds;
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _openAssistant() async {
    final question = _controller.currentQuestion;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sheet = QuestionAssistantSheet(
      question: question,
      allowAnswerReveal: _controller.explanationsVisibleForCurrent,
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

  Future<void> _openHighlightDialog(
    BookQuestion question,
    QuestionStudyData data,
  ) async {
    final result = await showDialog<List<HighlightSpan>>(
      context: context,
      builder: (dialogContext) {
        return _HighlightManageDialog(
          question: question,
          highlights: data.highlights,
        );
      },
    );
    if (result != null) {
      _updateStudyData(data.copyWith(highlights: result));
    }
  }

  Future<void> _openNotes(BookQuestion question) async {
    final currentData = _studyData.forQuestion(question.id);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return _NoteEditDialog(initialNote: currentData.note);
      },
    );
    if (result != null) {
      final updated = _studyData.forQuestion(question.id).copyWith(note: result);
      setState(() {
        _studyData = _studyData.withQuestion(question.id, updated);
      });
      widget.onStudyDataChanged(_studyData);
    }
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
    required this.studyData,
    required this.currentIndex,
    required this.onSelectQuestion,
  });

  final String title;
  final List<BookQuestion> questions;
  final StudyProgress progress;
  final StudyData studyData;
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
    final flaggedCount = questions
        .where((question) => studyData.forQuestion(question.id).isFlagged)
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
              if (flaggedCount > 0)
                _NavigatorStatChip(
                  label: 'Flagged',
                  value: '$flaggedCount',
                  color: Colors.orange,
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
                studyData: studyData,
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
    required this.studyData,
    required this.currentIndex,
    required this.onSelectQuestion,
  });

  final _QuestionGroup group;
  final StudyProgress progress;
  final StudyData studyData;
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
                isFlagged: studyData.forQuestion(entry.question.id).isFlagged,
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
    required this.isFlagged,
    required this.onTap,
  });

  final _QuestionEntry entry;
  final bool isCurrent;
  final QuestionProgress? progress;
  final bool isFlagged;
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
              if (isFlagged)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.flag, color: Colors.orange, size: 18),
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

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onEdit});

  final String note;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.amber.withValues(alpha: 0.1),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sticky_note_2, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  note,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.edit, size: 16, color: theme.hintColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteEditDialog extends StatefulWidget {
  const _NoteEditDialog({required this.initialNote});

  final String initialNote;

  @override
  State<_NoteEditDialog> createState() => _NoteEditDialogState();
}

class _NoteEditDialogState extends State<_NoteEditDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Question Note'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          maxLines: 8,
          minLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Write your personal notes for this question...',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        if (widget.initialNote.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(
              'Delete note',
              style: TextStyle(color: Colors.red.shade300),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _HighlightableText extends StatelessWidget {
  const _HighlightableText({
    required this.text,
    required this.field,
    required this.highlights,
    required this.onHighlight,
    required this.onRemoveHighlight,
    this.style,
  });

  final String text;
  final String field;
  final List<HighlightSpan> highlights;
  final ValueChanged<HighlightSpan> onHighlight;
  final ValueChanged<HighlightSpan> onRemoveHighlight;
  final TextStyle? style;

  TextSpan _buildTextSpan() {
    final spans = highlights.where((h) => h.field == field).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    if (spans.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final children = <TextSpan>[];
    var lastEnd = 0;

    for (final span in spans) {
      final start = span.start.clamp(0, text.length);
      final end = span.end.clamp(0, text.length);
      if (start >= end || start < lastEnd) continue;

      if (start > lastEnd) {
        children.add(TextSpan(text: text.substring(lastEnd, start), style: style));
      }

      children.add(TextSpan(
        text: text.substring(start, end),
        style: style?.copyWith(
          backgroundColor: Colors.yellow.withValues(alpha: 0.35),
        ),
      ));
      lastEnd = end;
    }

    if (lastEnd < text.length) {
      children.add(TextSpan(text: text.substring(lastEnd), style: style));
    }

    return TextSpan(children: children);
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Text.rich(_buildTextSpan()),
    );
  }
}

class _HighlightManageDialog extends StatefulWidget {
  const _HighlightManageDialog({
    required this.question,
    required this.highlights,
  });

  final BookQuestion question;
  final List<HighlightSpan> highlights;

  @override
  State<_HighlightManageDialog> createState() => _HighlightManageDialogState();
}

class _HighlightManageDialogState extends State<_HighlightManageDialog> {
  late final List<HighlightSpan> _highlights = List.from(widget.highlights);
  final TextEditingController _addController = TextEditingController();
  String _addField = 'prompt';

  void _addHighlight() {
    final searchText = _addController.text.trim();
    if (searchText.isEmpty) return;

    final source = _addField == 'prompt'
        ? widget.question.prompt
        : widget.question.explanation;
    final idx = source.toLowerCase().indexOf(searchText.toLowerCase());
    if (idx < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text not found in the selected field.')),
      );
      return;
    }

    setState(() {
      _highlights.add(HighlightSpan(
        field: _addField,
        start: idx,
        end: idx + searchText.length,
      ));
    });
    _addController.clear();
  }

  String _snippetFor(HighlightSpan span) {
    final source = span.field == 'prompt'
        ? widget.question.prompt
        : widget.question.explanation;
    final start = span.start.clamp(0, source.length);
    final end = span.end.clamp(0, source.length);
    if (start >= end) return '(invalid)';
    final text = source.substring(start, end);
    return text.length > 60 ? '${text.substring(0, 57)}...' : text;
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Highlights'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    decoration: const InputDecoration(
                      hintText: 'Type text to highlight...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addHighlight(),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _addField,
                  items: const [
                    DropdownMenuItem(value: 'prompt', child: Text('Stem')),
                    DropdownMenuItem(value: 'explanation', child: Text('Explanation')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _addField = v);
                  },
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addHighlight,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_highlights.isEmpty)
              Text(
                'No highlights yet. Type a phrase to highlight it.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _highlights.length,
                  itemBuilder: (context, index) {
                    final span = _highlights[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.yellow.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          span.field == 'prompt' ? 'Stem' : 'Expl',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      title: Text(
                        _snippetFor(span),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          setState(() => _highlights.removeAt(index));
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_highlights),
          child: const Text('Save'),
        ),
      ],
    );
  }
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
