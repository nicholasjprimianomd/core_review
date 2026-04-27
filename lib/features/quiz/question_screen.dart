import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/book_models.dart';
import '../../models/progress_models.dart';
import '../../models/study_data_models.dart';
import '../../models/text_highlight_utils.dart';
import '../../widgets/book_image_gallery.dart';
import '../../widgets/highlightable_selectable_text.dart';
import '../assistant/assistant_repository.dart';
import '../assistant/question_assistant_sheet.dart';
import '../exam/exam_session_models.dart';
import '../exam/exam_summary_screen.dart';
import '../progress/progress_repository.dart';
import 'answer_reveal_panel.dart';
import 'question_controller.dart';
import 'question_screen_shortcuts.dart';

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
    this.readOnlyAfterExam = false,
    this.onEndReview,
    this.onExamCompleted,
    this.onOpenFontSettings,
    this.hideExamSideNavigator = false,
    this.onHideExamSideNavigatorChanged,
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
  final bool readOnlyAfterExam;
  final VoidCallback? onEndReview;
  final Future<void> Function(ExamCompletionSnapshot snapshot)? onExamCompleted;
  final VoidCallback? onOpenFontSettings;
  final bool hideExamSideNavigator;
  final ValueChanged<bool>? onHideExamSideNavigatorChanged;

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _questionScrollController = ScrollController();
  final FocusNode _shortcutFocus = FocusNode(
    debugLabel: 'questionScreen.shortcuts',
  );

  /// Wide side panel hidden when true. Local state so toggling works on pushed
  /// routes (parent setState does not rebuild this screen).
  late bool _hideWideNavigator;
  double? _assistantPanelWidth;
  Timer? _examTicker;
  late final DateTime _examStartedAt;
  bool _examSummaryRouteOpen = false;

  late final QuestionController _controller = QuestionController(
    questions: widget.questions,
    progressRepository: widget.progressRepository,
    initialProgress: widget.initialProgress,
    initialIndex: widget.initialIndex,
    onProgressChanged: widget.readOnlyAfterExam
        ? null
        : widget.onProgressChanged,
    deferRevealUntilExamEnd: widget.readOnlyAfterExam
        ? false
        : (widget.examSession?.deferRevealUntilEnd ?? false),
    readOnlyAfterExam: widget.readOnlyAfterExam,
  );
  late final AssistantRepository _assistantRepository = AssistantRepository();
  late StudyData _studyData = widget.initialStudyData;

  QuestionStudyData get _currentStudyData =>
      _studyData.forQuestion(_controller.currentQuestion.id);

  QuestionStudyData _studyDataFor(BookQuestion question) =>
      _studyData.forQuestion(question.id);

  void _updateStudyData(QuestionStudyData data) {
    _updateStudyDataFor(_controller.currentQuestion, data);
  }

  void _updateStudyDataFor(BookQuestion question, QuestionStudyData data) {
    setState(() {
      _studyData = _studyData.withQuestion(question.id, data);
    });
    widget.onStudyDataChanged(_studyData);
  }

  void _updatePromptHighlightsFor(
    BookQuestion question,
    List<TextHighlightSpan> ranges,
  ) {
    _updateStudyDataFor(
      question,
      _studyDataFor(question).copyWith(promptHighlights: ranges),
    );
  }

  void _updateChoiceHighlightsFor(
    BookQuestion question,
    String choiceKey,
    List<TextHighlightSpan> ranges,
  ) {
    final map = Map<String, List<TextHighlightSpan>>.from(
      _studyDataFor(question).choiceHighlights,
    );
    if (ranges.isEmpty) {
      map.remove(choiceKey);
    } else {
      map[choiceKey] = ranges;
    }
    _updateStudyDataFor(
      question,
      _studyDataFor(question).copyWith(choiceHighlights: map),
    );
  }

  void _updateExplanationHighlightsFor(
    BookQuestion question,
    List<TextHighlightSpan> ranges,
  ) {
    _updateStudyDataFor(
      question,
      _studyDataFor(question).copyWith(explanationHighlights: ranges),
    );
  }

  void _toggleChoiceCrossOutFor(BookQuestion question, String choiceKey) {
    final current = _studyDataFor(question);
    final next = Set<String>.from(current.crossedOutChoices);
    if (next.contains(choiceKey)) {
      next.remove(choiceKey);
    } else {
      next.add(choiceKey);
    }
    _updateStudyDataFor(question, current.copyWith(crossedOutChoices: next));
  }

  void _toggleFlag() {
    final current = _currentStudyData;
    _updateStudyData(current.copyWith(isFlagged: !current.isFlagged));
  }

  @override
  void initState() {
    super.initState();
    _hideWideNavigator = widget.hideExamSideNavigator;
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
    FocusManager.instance.addListener(_onPrimaryFocusChanged);
  }

  /// Flutter only dispatches [Shortcuts] when some descendant of the
  /// [Shortcuts] widget holds primary focus. Clicking a [SelectableText],
  /// button, or scroll area can move focus elsewhere, which leaves the quiz
  /// needing a "click in the page" to re-arm shortcuts. Re-claim focus
  /// whenever the primary focus lands on a non-editable widget.
  void _onPrimaryFocusChanged() {
    if (!mounted) {
      return;
    }
    _maybeReclaimShortcutFocus();
  }

  bool _primaryFocusIsEditable() {
    final primary = FocusManager.instance.primaryFocus;
    final ctx = primary?.context;
    if (ctx == null) {
      return false;
    }
    final widget = ctx.widget;
    // [SelectableText] uses [EditableText] with readOnly=true under the hood;
    // only skip reclaim when the user is actually typing.
    return widget is EditableText && !widget.readOnly;
  }

  void _maybeReclaimShortcutFocus() {
    if (!_shortcutFocus.canRequestFocus) {
      return;
    }
    if (_shortcutFocus.hasPrimaryFocus) {
      return;
    }
    if (_primaryFocusIsEditable()) {
      return;
    }
    _shortcutFocus.requestFocus();
  }

  void _onShortcutLayerPointerUp(PointerUpEvent event) {
    // Wait for focus to settle from the tap before deciding whether to reclaim.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _maybeReclaimShortcutFocus();
    });
  }

  @override
  void didUpdateWidget(QuestionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hideExamSideNavigator != oldWidget.hideExamSideNavigator) {
      _hideWideNavigator = widget.hideExamSideNavigator;
    }
  }

  void _toggleHideWideNavigator() {
    if (widget.onHideExamSideNavigatorChanged == null) {
      return;
    }
    setState(() {
      _hideWideNavigator = !_hideWideNavigator;
    });
    widget.onHideExamSideNavigatorChanged!(_hideWideNavigator);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onPrimaryFocusChanged);
    _examTicker?.cancel();
    _questionScrollController.dispose();
    _shortcutFocus.dispose();
    _assistantRepository.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _scrollQuestionBodyByKeyboard(double delta) {
    if (!_quizKeyboardShortcutsEnabled) {
      return;
    }
    if (!_questionScrollController.hasClients) {
      return;
    }
    final position = _questionScrollController.position;
    final step = MediaQuery.sizeOf(context).height * 0.18;
    final target = (position.pixels + delta * step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    unawaited(
      _questionScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  bool get _quizKeyboardShortcutsEnabled {
    if (_controller.isSaving) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) {
      return true;
    }
    final editable = ctx.findAncestorWidgetOfExactType<EditableText>();
    if (editable != null && !editable.readOnly) {
      return false;
    }
    return true;
  }

  Map<ShortcutActivator, Intent> _quizShortcutsForQuestion(
    BookQuestion question,
  ) {
    final map = quizQuestionBaseShortcuts();
    mergeQuizChoiceLetterShortcuts(map, question.choices);
    return map;
  }

  Map<Type, Action<Intent>> _quizShortcutActions(BookQuestion question) {
    return <Type, Action<Intent>>{
      GoPreviousQuestionIntent: CallbackAction<GoPreviousQuestionIntent>(
        onInvoke: (_) {
          if (_quizKeyboardShortcutsEnabled && _controller.canGoPrevious) {
            _controller.goToPrevious();
          }
          return null;
        },
      ),
      GoNextQuestionIntent: CallbackAction<GoNextQuestionIntent>(
        onInvoke: (_) {
          if (_quizKeyboardShortcutsEnabled && _controller.canGoNext) {
            _controller.goToNext();
          }
          return null;
        },
      ),
      JumpFirstQuestionIntent: CallbackAction<JumpFirstQuestionIntent>(
        onInvoke: (_) {
          if (_quizKeyboardShortcutsEnabled && _controller.currentIndex > 0) {
            _controller.jumpToIndex(0);
          }
          return null;
        },
      ),
      JumpLastQuestionIntent: CallbackAction<JumpLastQuestionIntent>(
        onInvoke: (_) {
          if (_quizKeyboardShortcutsEnabled &&
              _controller.currentIndex < _controller.questionCount - 1) {
            _controller.jumpToIndex(_controller.questionCount - 1);
          }
          return null;
        },
      ),
      ScrollQuestionUpIntent: CallbackAction<ScrollQuestionUpIntent>(
        onInvoke: (_) {
          _scrollQuestionBodyByKeyboard(-1);
          return null;
        },
      ),
      ScrollQuestionDownIntent: CallbackAction<ScrollQuestionDownIntent>(
        onInvoke: (_) {
          _scrollQuestionBodyByKeyboard(1);
          return null;
        },
      ),
      SubmitOrAdvanceQuestionIntent:
          CallbackAction<SubmitOrAdvanceQuestionIntent>(
            onInvoke: (_) {
              _handleSubmitOrAdvanceShortcut();
              return null;
            },
          ),
      OpenQuestionListIntent: CallbackAction<OpenQuestionListIntent>(
        onInvoke: (_) {
          if (!_quizKeyboardShortcutsEnabled) {
            return null;
          }
          final showWide =
              MediaQuery.sizeOf(context).width >= 1200 && !_hideWideNavigator;
          if (!showWide) {
            _openQuestionNavigator();
          }
          return null;
        },
      ),
      CloseEndDrawerIntent: CallbackAction<CloseEndDrawerIntent>(
        onInvoke: (_) {
          if (!_quizKeyboardShortcutsEnabled) {
            return null;
          }
          final scaffold = _scaffoldKey.currentState;
          if (scaffold != null && scaffold.isEndDrawerOpen) {
            scaffold.closeEndDrawer();
          }
          return null;
        },
      ),
      ShowKeyboardShortcutsHelpIntent:
          CallbackAction<ShowKeyboardShortcutsHelpIntent>(
            onInvoke: (_) {
              if (!_quizKeyboardShortcutsEnabled) {
                return null;
              }
              showQuizKeyboardShortcutsDialog(context);
              return null;
            },
          ),
      CopyQuestionHighlightsIntent:
          CallbackAction<CopyQuestionHighlightsIntent>(
            onInvoke: (_) {
              unawaited(_copyAllQuestionHighlightsToClipboard());
              return null;
            },
          ),
      UndoAnswerIntent: CallbackAction<UndoAnswerIntent>(
        onInvoke: (_) {
          if (_controller.canUndoCurrentAnswer) {
            unawaited(_controller.undoCurrentAnswer());
          }
          return null;
        },
      ),
      SelectChoiceDigitIntent: CallbackAction<SelectChoiceDigitIntent>(
        onInvoke: (SelectChoiceDigitIntent intent) {
          _handleSelectChoiceDigit(question, intent.digitOneToNine);
          return null;
        },
      ),
      SelectChoiceKeyIntent: CallbackAction<SelectChoiceKeyIntent>(
        onInvoke: (SelectChoiceKeyIntent intent) {
          _handleSelectChoiceKey(question, intent.choiceKey);
          return null;
        },
      ),
    };
  }

  void _handleSubmitOrAdvanceShortcut() {
    if (!_quizKeyboardShortcutsEnabled) {
      return;
    }
    if (_controller.isSaving) {
      return;
    }
    if (widget.readOnlyAfterExam) {
      if (_controller.shouldUseNextPartAction &&
          _controller.canAdvanceToNextPart) {
        unawaited(_controller.submitCurrentPartAndAdvance());
      } else if (_controller.canGoNext) {
        _controller.goToNext();
      }
      return;
    }
    if (_controller.shouldUseNextPartAction &&
        _controller.canAdvanceToNextPart) {
      if (_controller.canSubmit) {
        unawaited(_controller.submitCurrentAnswer());
      }
      return;
    }
    if (_controller.canSubmit) {
      unawaited(_controller.submitCurrentAnswer());
      return;
    }
    if (_controller.currentQuestionProgress != null && _controller.canGoNext) {
      _controller.goToNext();
    }
  }

  void _handleSelectChoiceDigit(BookQuestion question, int digitOneToNine) {
    if (!_quizKeyboardShortcutsEnabled ||
        widget.readOnlyAfterExam ||
        _controller.currentQuestionProgress != null) {
      return;
    }
    if (question.isMatching) {
      // Matching questions need a per-item selector; skip digit shortcut.
      return;
    }
    final entries = question.choices.entries.toList(growable: false);
    if (digitOneToNine < 1 || digitOneToNine > entries.length) {
      return;
    }
    _controller.selectChoice(entries[digitOneToNine - 1].key);
  }

  void _handleSelectChoiceKey(BookQuestion question, String choiceKey) {
    if (!_quizKeyboardShortcutsEnabled ||
        widget.readOnlyAfterExam ||
        _controller.currentQuestionProgress != null) {
      return;
    }
    if (question.isMatching) {
      return;
    }
    if (!question.choices.containsKey(choiceKey)) {
      return;
    }
    _controller.selectChoice(choiceKey);
  }

  Future<void> _copyAllQuestionHighlightsToClipboard() async {
    if (!_quizKeyboardShortcutsEnabled) {
      return;
    }
    final q = _controller.currentQuestion;
    final d = _currentStudyData;
    final parts = <String>[];

    final prompt = mergedHighlightedText(q.prompt, d.promptHighlights);
    if (prompt.isNotEmpty) {
      parts.add('Prompt: $prompt');
    }
    for (final e in q.choices.entries) {
      final h = d.choiceHighlights[e.key] ?? const <TextHighlightSpan>[];
      final t = mergedHighlightedText(e.value, h);
      if (t.isNotEmpty) {
        parts.add('Choice ${e.key}: $t');
      }
    }
    final qp = _controller.currentQuestionProgress;
    final explVisible = _controller.explanationsVisibleForCurrent;
    if (qp != null && explVisible && q.explanation.isNotEmpty) {
      final ex = mergedHighlightedText(q.explanation, d.explanationHighlights);
      if (ex.isNotEmpty) {
        parts.add('Explanation: $ex');
      }
    }
    if (parts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No highlights on this question')),
        );
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Highlights copied')));
    }
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
    if (exam == null ||
        widget.readOnlyAfterExam ||
        _examSummaryRouteOpen ||
        !mounted) {
      return;
    }

    if (!timeUp) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('End exam'),
                content: const Text('End this exam and view your summary?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('End exam'),
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
    final wantsReview = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
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
    _examSummaryRouteOpen = false;

    if (!mounted) {
      return;
    }

    await widget.onExamCompleted?.call(
      ExamCompletionSnapshot(
        title: widget.title,
        questionIds: widget.questions.map((q) => q.id).toList(growable: false),
        examMode: exam.mode,
        startedAt: _examStartedAt,
        endedAt: endedAt,
        timeLimit: exam.timeLimit,
      ),
    );

    if (wantsReview == true && mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => QuestionScreen(
            title: '${widget.title} (review)',
            content: widget.content,
            questions: widget.questions,
            progressRepository: widget.progressRepository,
            initialProgress: _controller.progress,
            initialStudyData: _studyData,
            initialIndex: 0,
            themeMode: widget.themeMode,
            onToggleTheme: widget.onToggleTheme,
            onProgressChanged: widget.onProgressChanged,
            onStudyDataChanged: widget.onStudyDataChanged,
            readOnlyAfterExam: true,
            onEndReview: () => Navigator.of(context).pop(),
            onOpenFontSettings: widget.onOpenFontSettings,
            hideExamSideNavigator: _hideWideNavigator,
            onHideExamSideNavigatorChanged:
                widget.onHideExamSideNavigatorChanged,
          ),
        ),
      );
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  List<Widget> _buildQuestionParts({
    required List<BookQuestion> questions,
    required bool examDefer,
  }) {
    final isMultipart = questions.length > 1;
    return [
      if (isMultipart)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Multipart case',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      for (var i = 0; i < questions.length; i++) ...[
        if (i > 0) const Divider(height: 40),
        ..._buildQuestionPart(
          question: questions[i],
          examDefer: examDefer,
          isMultipart: isMultipart,
        ),
      ],
    ];
  }

  List<Widget> _buildQuestionPart({
    required BookQuestion question,
    required bool examDefer,
    required bool isMultipart,
  }) {
    final questionProgress = _controller.questionProgressFor(question);
    final selectedChoice = _controller.selectedChoiceFor(question);
    final explanationsVisible = _controller.explanationsVisibleFor(question);
    final studyData = _studyDataFor(question);
    final hasRevealedAnswer = questionProgress?.isRevealed ?? false;

    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text(question.bookTitle)),
          if (question.topicTitle != null)
            Chip(label: Text(question.topicTitle!)),
          Chip(
            label: Text('${question.chapterNumber}. ${question.chapterTitle}'),
          ),
          if (question.sectionTitle != null)
            Chip(label: Text(question.sectionTitle!)),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        'Question ${question.displayNumber}',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      HighlightableSelectableText(
        text: question.prompt,
        style: Theme.of(context).textTheme.bodyLarge,
        highlights: studyData.promptHighlights,
        onHighlightsChanged: (ranges) =>
            _updatePromptHighlightsFor(question, ranges),
      ),
      if (widget.content.stemImageAssetsForQuestion(question).isNotEmpty) ...[
        const SizedBox(height: 20),
        BookImageGallery(
          imageAssets: widget.content.stemImageAssetsForQuestion(question),
        ),
      ],
      if (!widget.readOnlyAfterExam && !isMultipart) ...[
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
            OutlinedButton.icon(
              onPressed: () => _openAssistant(autoRunReferenceSearch: true),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Find CTC / War Machine pages'),
            ),
          ],
        ),
      ],
      const SizedBox(height: 20),
      Text(
        question.isMatching
            ? 'Match each item to an answer'
            : 'Choose your answer',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      if (question.choices.isEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Answer choices are missing for this question (${question.id}).',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ] else if (question.isMatching) ...[
        _MatchingAnswerBank(choices: question.choices),
        const SizedBox(height: 12),
        for (final item in question.matchingItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MatchingItemRow(
              question: question,
              item: item,
              selectedChoice:
                  _controller.matchingSelectionsFor(question)[item.label] ?? '',
              revealed: explanationsVisible,
              progress: questionProgress,
              enabled: !widget.readOnlyAfterExam && questionProgress == null,
              onSelect: (key) => _controller.selectMatchingChoiceFor(
                question,
                item.label,
                key,
              ),
            ),
          ),
      ] else
        for (final entry in question.choices.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ChoiceTile(
              optionLabel: entry.key,
              optionText: entry.value,
              textHighlights:
                  studyData.choiceHighlights[entry.key] ??
                  const <TextHighlightSpan>[],
              onTextHighlightsChanged: (ranges) =>
                  _updateChoiceHighlightsFor(question, entry.key, ranges),
              isSelected: selectedChoice == entry.key,
              isCorrectAnswer:
                  explanationsVisible && question.correctChoice == entry.key,
              isIncorrectSelection:
                  explanationsVisible &&
                  questionProgress != null &&
                  questionProgress.selectedChoice == entry.key &&
                  !questionProgress.isCorrect,
              isCrossedOut: studyData.crossedOutChoices.contains(entry.key),
              enabled: !widget.readOnlyAfterExam && questionProgress == null,
              onTap: () => _controller.selectChoiceFor(question, entry.key),
              onToggleCrossOut:
                  !widget.readOnlyAfterExam && questionProgress == null
                  ? () => _toggleChoiceCrossOutFor(question, entry.key)
                  : null,
            ),
          ),
      const SizedBox(height: 8),
      if (!widget.readOnlyAfterExam)
        FilledButton.icon(
          onPressed: _controller.canSubmitQuestion(question)
              ? () => _controller.submitAnswerFor(question)
              : null,
          icon: _controller.isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  examDefer || isMultipart
                      ? Icons.check_circle_outline
                      : Icons.visibility,
                ),
          label: Text(examDefer || isMultipart ? 'Save answer' : 'Show Answer'),
        ),
      if (_controller.canUndoQuestion(question)) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _controller.undoQuestion(question),
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('Change Answer'),
        ),
      ],
      if (!widget.readOnlyAfterExam &&
          questionProgress != null &&
          !hasRevealedAnswer) ...[
        const SizedBox(height: 16),
        Text(
          examDefer
              ? 'Answer saved. Explanations and scores stay hidden until you end the exam.'
              : 'Answer saved. Explanations appear after all parts are answered.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
      if (widget.readOnlyAfterExam && questionProgress == null) ...[
        const SizedBox(height: 16),
        Text(
          'No answer was recorded for this question in that exam.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: Theme.of(context).hintColor,
          ),
        ),
      ],
      if (studyData.hasNote) ...[
        const SizedBox(height: 16),
        if (widget.readOnlyAfterExam)
          Card(
            color: Colors.amber.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      studyData.note,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          _NoteCard(note: studyData.note, onEdit: () => _openNotes(question)),
      ],
      if (questionProgress != null && explanationsVisible) ...[
        const SizedBox(height: 16),
        AnswerRevealPanel(
          content: widget.content,
          question: question,
          progress: questionProgress,
          explanationHighlights: studyData.explanationHighlights,
          onExplanationHighlightsChanged: (ranges) =>
              _updateExplanationHighlightsFor(question, ranges),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final showWideNavigator = screenWidth >= 1200 && !_hideWideNavigator;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        final question = _controller.currentQuestion;
        final examDefer =
            !widget.readOnlyAfterExam &&
            widget.examSession?.deferRevealUntilEnd == true;

        final currentStudyData = _currentStudyData;

        final navigatorPanel = _QuestionNavigatorPanel(
          title: widget.title,
          questions: _controller.questions,
          progress: _controller.progress,
          studyData: _studyData,
          currentIndex: _controller.currentIndex,
          onSelectQuestion: (index) {
            if (!showWideNavigator) {
              Navigator.of(context).maybePop();
            }
            _controller.jumpToIndex(index);
          },
        );

        return Scaffold(
          key: _scaffoldKey,
          endDrawer: showWideNavigator
              ? null
              : Drawer(width: 360, child: SafeArea(child: navigatorPanel)),
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
                  onPressed: _controller.isSaving
                      ? null
                      : () => _endExamSession(),
                  tooltip: 'End exam',
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              if (screenWidth >= 1200 &&
                  widget.onHideExamSideNavigatorChanged != null)
                IconButton(
                  onPressed: _toggleHideWideNavigator,
                  tooltip: _hideWideNavigator
                      ? 'Show question list panel'
                      : 'Hide question list panel',
                  icon: Icon(
                    _hideWideNavigator
                        ? Icons.view_sidebar_outlined
                        : Icons.vertical_split_outlined,
                  ),
                ),
              if (widget.readOnlyAfterExam)
                TextButton(
                  onPressed: widget.onEndReview,
                  child: const Text('Done'),
                ),
              if (!widget.readOnlyAfterExam) ...[
                IconButton(
                  onPressed: _toggleFlag,
                  tooltip: currentStudyData.isFlagged
                      ? 'Unflag question'
                      : 'Flag question',
                  icon: Icon(
                    currentStudyData.isFlagged
                        ? Icons.flag
                        : Icons.flag_outlined,
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
              ],
              if (!showWideNavigator)
                IconButton(
                  onPressed: _openQuestionNavigator,
                  tooltip: 'Question list',
                  icon: const Icon(Icons.toc_outlined),
                ),
              IconButton(
                tooltip: 'Keyboard shortcuts (? or Ctrl+/)',
                onPressed: () => showQuizKeyboardShortcutsDialog(context),
                icon: const Icon(Icons.help_outline),
              ),
              if (!widget.readOnlyAfterExam)
                IconButton(
                  onPressed: _openAssistant,
                  tooltip: 'Study assistant',
                  icon: const Icon(Icons.auto_awesome_outlined),
                ),
              if (widget.onOpenFontSettings != null)
                IconButton(
                  onPressed: widget.onOpenFontSettings,
                  tooltip: 'Text size',
                  icon: const Icon(Icons.format_size),
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
          body: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerUp: _onShortcutLayerPointerUp,
            child: Shortcuts(
              shortcuts: _quizShortcutsForQuestion(question),
              child: Actions(
                actions: _quizShortcutActions(question),
                child: Focus(
                  focusNode: _shortcutFocus,
                  autofocus: true,
                  child: SafeArea(
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
                                  controller: _questionScrollController,
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: _buildQuestionParts(
                                      questions:
                                          _controller.currentMultipartQuestions,
                                      examDefer: examDefer,
                                    ),
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              ColoredBox(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainer,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed:
                                              _controller.canGoPreviousGroup
                                              ? _controller.goToPreviousGroup
                                              : null,
                                          icon: const Icon(Icons.chevron_left),
                                          label: const Text('Previous'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child:
                                            widget.examSession != null &&
                                                !widget.readOnlyAfterExam &&
                                                !_controller.canGoNextGroup
                                            ? FilledButton.icon(
                                                onPressed: _controller.isSaving
                                                    ? null
                                                    : () => unawaited(
                                                        _endExamSession(),
                                                      ),
                                                icon: const Icon(
                                                  Icons.stop_circle_outlined,
                                                ),
                                                label: const Text('End exam'),
                                              )
                                            : FilledButton.icon(
                                                onPressed:
                                                    _controller.canGoNextGroup
                                                    ? _controller.goToNextGroup
                                                    : null,
                                                icon: const Icon(
                                                  Icons.chevron_right,
                                                ),
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
                        if (showWideNavigator) ...[
                          const VerticalDivider(width: 1),
                          SizedBox(width: 340, child: navigatorPanel),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
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

  Future<void> _openAssistant({bool autoRunReferenceSearch = false}) async {
    final question = _controller.currentQuestion;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sheet = QuestionAssistantSheet(
      question: question,
      allowAnswerReveal: _controller.explanationsVisibleForCurrent,
      assistantRepository: _assistantRepository,
      autoRunReferenceSearch: autoRunReferenceSearch,
    );

    if (screenWidth >= 780) {
      final defaultPanelWidth = screenWidth >= 1500
          ? 820.0
          : (screenWidth * 0.58).clamp(460.0, 820.0).toDouble();
      final minPanelWidth = 320.0;
      final maxPanelWidth = (screenWidth * 0.85)
          .clamp(minPanelWidth, 1200.0)
          .toDouble();
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

  Future<void> _openNotes(BookQuestion question) async {
    final currentData = _studyData.forQuestion(question.id);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return _NoteEditDialog(initialNote: currentData.note);
      },
    );
    if (result != null) {
      final updated = _studyData
          .forQuestion(question.id)
          .copyWith(note: result);
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
    if (oldWidget.initialWidth != widget.initialWidth &&
        _dragStartWidth == null) {
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
    final correctCount = questions.where((question) {
      final questionProgress = progress.answers[question.id];
      return questionProgress?.isRevealed == true &&
          (questionProgress?.isCorrect ?? false);
    }).length;
    final incorrectCount = questions.where((question) {
      final questionProgress = progress.answers[question.id];
      return questionProgress?.isRevealed == true &&
          !(questionProgress?.isCorrect ?? true);
    }).length;
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
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
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
    final correctCount = group.entries.where((entry) {
      final questionProgress = progress.answers[entry.question.id];
      return questionProgress?.isRevealed == true &&
          (questionProgress?.isCorrect ?? false);
    }).length;

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
        color:
            chipColor?.withValues(alpha: 0.12) ??
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

    groups.last.entries.add(_QuestionEntry(index: index, question: question));
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
  const _QuestionEntry({required this.index, required this.question});

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
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialNote,
  );

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

class _ChoiceTile extends StatefulWidget {
  const _ChoiceTile({
    required this.optionLabel,
    required this.optionText,
    required this.textHighlights,
    required this.onTextHighlightsChanged,
    required this.isSelected,
    required this.isCorrectAnswer,
    required this.isIncorrectSelection,
    required this.isCrossedOut,
    required this.enabled,
    required this.onTap,
    required this.onToggleCrossOut,
  });

  final String optionLabel;
  final String optionText;
  final List<TextHighlightSpan> textHighlights;
  final ValueChanged<List<TextHighlightSpan>> onTextHighlightsChanged;
  final bool isSelected;
  final bool isCorrectAnswer;
  final bool isIncorrectSelection;
  final bool isCrossedOut;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onToggleCrossOut;

  @override
  State<_ChoiceTile> createState() => _ChoiceTileState();
}

class _ChoiceTileState extends State<_ChoiceTile> {
  bool _hovered = false;

  bool get _hoverVisualActive =>
      widget.enabled &&
      _hovered &&
      !widget.isCorrectAnswer &&
      !widget.isIncorrectSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? borderColor;
    Color? backgroundColor;

    if (widget.isCorrectAnswer) {
      borderColor = Colors.green;
      backgroundColor = Colors.green.withValues(alpha: 0.08);
    } else if (widget.isIncorrectSelection) {
      borderColor = Colors.red;
      backgroundColor = Colors.red.withValues(alpha: 0.08);
    } else if (widget.isSelected) {
      borderColor = theme.colorScheme.primary;
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.08);
    }

    if (_hoverVisualActive) {
      final hoverTint = theme.colorScheme.onSurface.withValues(alpha: 0.08);
      backgroundColor = backgroundColor != null
          ? Color.alphaBlend(hoverTint, backgroundColor)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
      borderColor ??= theme.colorScheme.outline.withValues(alpha: 0.45);
    }

    final bool showCrossOut =
        widget.isCrossedOut &&
        !widget.isCorrectAnswer &&
        !widget.isIncorrectSelection;
    final Color disabledForeground = theme.colorScheme.onSurface.withValues(
      alpha: 0.38,
    );
    final TextStyle? choiceTextStyle = showCrossOut
        ? theme.textTheme.bodyLarge?.copyWith(
            decoration: TextDecoration.lineThrough,
            decorationThickness: 2,
            decorationColor: disabledForeground,
            color: disabledForeground,
          )
        : theme.textTheme.bodyLarge;

    return MouseRegion(
      onEnter: (_) {
        if (widget.enabled &&
            !widget.isCorrectAnswer &&
            !widget.isIncorrectSelection) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor ?? theme.dividerColor,
              width: borderColor == null ? 1 : 2,
            ),
          ),
          child: _ChoiceTapDetector(
            enabled: widget.enabled,
            onTap: widget.onTap,
            onSecondaryTap: widget.onToggleCrossOut,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Opacity(
                    opacity: showCrossOut ? 0.45 : 1,
                    child: CircleAvatar(
                      radius: 16,
                      child: Text(widget.optionLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: HighlightableSelectableText(
                      text: widget.optionText,
                      style: choiceTextStyle,
                      highlights: widget.textHighlights,
                      onHighlightsChanged: widget.onTextHighlightsChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [InkWell.onTap] does not fire over [SelectableText] on web; use raw pointers so
/// a short click anywhere on the row selects the choice, while drag still highlights.
class _ChoiceTapDetector extends StatefulWidget {
  const _ChoiceTapDetector({
    required this.enabled,
    required this.onTap,
    required this.child,
    this.onSecondaryTap,
  });

  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final Widget child;

  @override
  State<_ChoiceTapDetector> createState() => _ChoiceTapDetectorState();
}

class _MatchingAnswerBank extends StatelessWidget {
  const _MatchingAnswerBank({required this.choices});

  final Map<String, String> choices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Answer choices',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in choices.entries)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    TextSpan(
                      text: '${entry.key}. ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: entry.value),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MatchingItemRow extends StatelessWidget {
  const _MatchingItemRow({
    required this.question,
    required this.item,
    required this.selectedChoice,
    required this.revealed,
    required this.progress,
    required this.enabled,
    required this.onSelect,
  });

  final BookQuestion question;
  final MatchingItem item;
  final String selectedChoice;
  final bool revealed;
  final QuestionProgress? progress;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final submittedChoice =
        progress?.itemSelections?[item.label] ?? selectedChoice;
    final bool isCorrect =
        revealed &&
        submittedChoice.isNotEmpty &&
        submittedChoice == item.correctChoice;
    final bool isIncorrect =
        revealed &&
        submittedChoice.isNotEmpty &&
        submittedChoice != item.correctChoice;

    Color? borderColor;
    Color? background;
    if (isCorrect) {
      borderColor = Colors.green;
      background = Colors.green.withValues(alpha: 0.08);
    } else if (isIncorrect) {
      borderColor = Colors.red;
      background = Colors.red.withValues(alpha: 0.08);
    } else if (submittedChoice.isNotEmpty) {
      borderColor = theme.colorScheme.primary;
      background = theme.colorScheme.primary.withValues(alpha: 0.06);
    }

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor ?? theme.dividerColor,
          width: borderColor == null ? 1 : 2,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (revealed)
                Expanded(
                  child: Text(
                    'Correct: ${item.correctChoice}. '
                    '${question.choices[item.correctChoice] ?? ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    submittedChoice.isEmpty
                        ? 'Select an answer'
                        : 'Your answer: $submittedChoice',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          if (item.hasImage) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                item.imageAsset,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in question.choices.entries)
                _MatchingChoiceButton(
                  label: entry.key,
                  selected: submittedChoice == entry.key,
                  isCorrectAnswer: revealed && entry.key == item.correctChoice,
                  isIncorrectSelection:
                      revealed &&
                      submittedChoice == entry.key &&
                      submittedChoice != item.correctChoice,
                  enabled: enabled,
                  onTap: enabled ? () => onSelect(entry.key) : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MatchingChoiceButton extends StatelessWidget {
  const _MatchingChoiceButton({
    required this.label,
    required this.selected,
    required this.isCorrectAnswer,
    required this.isIncorrectSelection,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isCorrectAnswer;
  final bool isIncorrectSelection;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color background;
    Color foreground;
    Color border;
    if (isCorrectAnswer) {
      background = Colors.green.withValues(alpha: 0.16);
      foreground = Colors.green.shade800;
      border = Colors.green;
    } else if (isIncorrectSelection) {
      background = Colors.red.withValues(alpha: 0.16);
      foreground = Colors.red.shade800;
      border = Colors.red;
    } else if (selected) {
      background = theme.colorScheme.primary.withValues(alpha: 0.14);
      foreground = theme.colorScheme.primary;
      border = theme.colorScheme.primary;
    } else {
      background = theme.colorScheme.surface;
      foreground = theme.colorScheme.onSurface;
      border = theme.dividerColor;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(
            color: border,
            width: selected || isCorrectAnswer || isIncorrectSelection ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ChoiceTapDetectorState extends State<_ChoiceTapDetector> {
  Offset? _pointerDownGlobal;
  Offset? _secondaryDownGlobal;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            if (widget.onSecondaryTap != null) {
              _secondaryDownGlobal = event.position;
            }
            return;
          }
          if (!widget.enabled) {
            return;
          }
          _pointerDownGlobal = event.position;
        },
        onPointerCancel: (_) {
          _pointerDownGlobal = null;
          _secondaryDownGlobal = null;
        },
        onPointerUp: (event) {
          final secondaryStart = _secondaryDownGlobal;
          _secondaryDownGlobal = null;
          if (secondaryStart != null && widget.onSecondaryTap != null) {
            final moved = (event.position - secondaryStart).distance;
            if (moved <= kTouchSlop) {
              widget.onSecondaryTap!();
              _pointerDownGlobal = null;
              return;
            }
          }
          if (!widget.enabled || _pointerDownGlobal == null) {
            _pointerDownGlobal = null;
            return;
          }
          final moved = (event.position - _pointerDownGlobal!).distance;
          _pointerDownGlobal = null;
          if (moved <= kTouchSlop) {
            widget.onTap();
          }
        },
        child: widget.child,
      ),
    );
  }
}
