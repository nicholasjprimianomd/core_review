import 'package:flutter/material.dart';

import '../../models/book_models.dart';
import 'assistant_repository.dart';
import 'reference_pdf_viewer.dart';

class QuestionAssistantSheet extends StatefulWidget {
  const QuestionAssistantSheet({
    required this.question,
    required this.allowAnswerReveal,
    required this.assistantRepository,
    this.autoRunReferenceSearch = false,
    super.key,
  });

  final BookQuestion question;
  final bool allowAnswerReveal;
  final AssistantRepository assistantRepository;

  /// When true, immediately kick off the Crack the Core / War Machine
  /// reference page search as soon as the sheet is built. Used when the
  /// sheet is launched from a per-question "Find CTC / War Machine pages"
  /// shortcut so the user lands on a loading state pre-wired to that task.
  final bool autoRunReferenceSearch;

  @override
  State<QuestionAssistantSheet> createState() => _QuestionAssistantSheetState();
}

class _QuestionAssistantSheetState extends State<QuestionAssistantSheet> {
  final TextEditingController _customPromptController = TextEditingController();

  bool _isExplainingAllChoices = false;
  bool _isAskingCustom = false;
  bool _isSearchingRefBooks = false;
  String? _errorMessage;
  AssistantReply? _allChoicesReply;
  AssistantReply? _customReply;
  ReferenceBooksSearchResult? _referenceResult;
  bool _expandReferenceMatches = false;

  static const int _referenceMatchTeaserCount = 3;

  @override
  void initState() {
    super.initState();
    if (widget.autoRunReferenceSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _searchReferenceBooks();
      });
    }
  }

  @override
  void dispose() {
    _customPromptController.dispose();
    super.dispose();
  }

  String _explainAllChoicesCorePrompt() {
    if (widget.allowAnswerReveal) {
      return 'You are helping a resident prepare for the American Board of Radiology (ABR) Core '
          'Radiology Exam. Using ONLY the question stem, answer choices, and any revealed '
          'explanation or references in the study context, explain EVERY listed answer option '
          'in order (use the same option letters as in context). For each option: what it means '
          'clinically and on imaging; how it relates to the stem; and why it is correct or '
          'incorrect for this case, with Core-style discriminating features the boards favor. '
          'End with a short summary of the main teaching point.';
    }
    return 'You are helping a resident prepare for the American Board of Radiology (ABR) Core '
        'Radiology Exam. Using ONLY the question stem and answer choices in the study context, '
        'discuss EVERY listed answer option in order (same letters as in context): the imaging '
        'and disease concepts each option implies and how each could relate to the differential '
        'suggested by the stem. Do NOT state which option is correct, do NOT rank the choices, '
        'and do NOT imply which is most likely. End with brief, spoiler-free study tips.';
  }

  Future<void> _explainAllChoicesCore() async {
    setState(() {
      _isExplainingAllChoices = true;
      _errorMessage = null;
      _allChoicesReply = null;
    });

    try {
      final reply = await widget.assistantRepository.askQuestion(
        question: widget.question,
        userPrompt: _explainAllChoicesCorePrompt(),
        allowAnswerReveal: widget.allowAnswerReveal,
        includeWebImages: false,
        assistantTask: 'explainAllChoices',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _allChoicesReply = reply;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExplainingAllChoices = false;
        });
      }
    }
  }

  Future<void> _askCustom() async {
    final text = _customPromptController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'Type a question below.';
      });
      return;
    }

    setState(() {
      _isAskingCustom = true;
      _errorMessage = null;
      _customReply = null;
    });

    try {
      final reply = await widget.assistantRepository.askQuestion(
        question: widget.question,
        userPrompt: text,
        allowAnswerReveal: widget.allowAnswerReveal,
        includeWebImages: false,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _customReply = reply;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAskingCustom = false;
        });
      }
    }
  }

  Future<void> _searchReferenceBooks() async {
    setState(() {
      _isSearchingRefBooks = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.assistantRepository.searchReferenceBooks(
        question: widget.question,
        allowAnswerReveal: widget.allowAnswerReveal,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _referenceResult = result;
        _expandReferenceMatches = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString().replaceFirst('Bad state: ', '');
        _referenceResult = null;
        _expandReferenceMatches = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingRefBooks = false;
        });
      }
    }
  }

  Future<void> _showFullReferencePage(
    BuildContext context,
    ReferenceBookMatch match,
  ) async {
    final body =
        match.fullText.isNotEmpty ? match.fullText : match.excerpt;
    if (body.isEmpty) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final h = MediaQuery.of(ctx).size.height;
        return AlertDialog(
          title: Text('${match.bookLabel} · p. ${match.page}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Text from the PDF index (figures are not included). '
                  'If the index was built with a per-page character cap, text may be truncated.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).hintColor,
                      ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: h * 0.62),
                  child: SingleChildScrollView(
                    child: SelectionArea(
                      child: _FormattedBookText(body),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (match.pdfUrl.trim().isNotEmpty) ...[
              TextButton.icon(
                onPressed: () async {
                  await showReferencePdfViewer(
                    ctx,
                    pdfUrl: match.pdfUrl,
                    page: match.page,
                  );
                },
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text('PDF (p. ${match.page})'),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildVisibleReferenceMatchCards(BuildContext context) {
    final result = _referenceResult;
    if (result == null || result.matches.isEmpty) {
      return const <Widget>[];
    }
    final matches = result.matches;
    final showAll =
        _expandReferenceMatches || matches.length <= _referenceMatchTeaserCount;
    final visible = showAll
        ? matches
        : matches.sublist(0, _referenceMatchTeaserCount);
    final children = <Widget>[];
    for (final m in visible) {
      children.add(_ReferenceMatchCard(
        match: m,
        onOpenPdf: m.pdfUrl.trim().isEmpty
            ? null
            : () => showReferencePdfViewer(
                  context,
                  pdfUrl: m.pdfUrl,
                  page: m.page,
                ),
        onOpenFullText: () => _showFullReferencePage(context, m),
      ));
      children.add(const SizedBox(height: 8));
    }
    if (matches.length > _referenceMatchTeaserCount) {
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              setState(() {
                _expandReferenceMatches = !_expandReferenceMatches;
              });
            },
            child: Text(
              _expandReferenceMatches
                  ? 'Show top $_referenceMatchTeaserCount only'
                  : 'More relevant pages (${matches.length - _referenceMatchTeaserCount} more)',
            ),
          ),
        ),
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final isBusy = _isExplainingAllChoices ||
        _isAskingCustom ||
        _isSearchingRefBooks;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        top: 16,
        right: 16,
        bottom: 16 + viewInsets.bottom,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Study Assistant',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message:
                  'Walks through every answer choice with ABR Core Exam-style reasoning. '
                  'Uses the same context rules as the rest of the assistant (no spoilers in study mode).',
              child: FilledButton.icon(
                onPressed: isBusy ? null : _explainAllChoicesCore,
                icon: _isExplainingAllChoices
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.checklist_outlined),
                label: const Text('Explain every answer'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _customPromptController,
            minLines: 2,
            maxLines: 5,
            textInputAction: TextInputAction.send,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Ask about this question',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              alignLabelWithHint: false,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              suffixIcon: _isAskingCustom
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      onPressed: isBusy ? null : _askCustom,
                      tooltip: 'Ask',
                      icon: const Icon(Icons.send_outlined),
                    ),
            ),
            onSubmitted: isBusy ? null : (_) => _askCustom(),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_allChoicesReply != null &&
                    _allChoicesReply!.answer.trim().isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Every answer',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectionArea(
                        child: Text(_allChoicesReply!.answer),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_customReply != null &&
                    _customReply!.answer.trim().isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Follow-up',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectionArea(
                        child: Text(_customReply!.answer),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_isSearchingRefBooks && _referenceResult == null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Crack the Core / War Machine',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Searching CTC 1, CTC 2, and War Machine...',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (_referenceResult != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Crack the Core / War Machine',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Indexed pages from CTC 1, CTC 2, and War Machine only; open the PDF for the real page.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_referenceResult!.searchMeta != null &&
                      _referenceResult!.searchMeta!.hasDisplayableContent) ...[
                    _ReferenceSearchMetaCard(
                      meta: _referenceResult!.searchMeta!,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_referenceResult!.message != null &&
                      _referenceResult!.message!.trim().isNotEmpty &&
                      _referenceResult!.matches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _referenceResult!.message!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ..._buildVisibleReferenceMatchCards(context),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceMatchCard extends StatelessWidget {
  const _ReferenceMatchCard({
    required this.match,
    this.onOpenPdf,
    required this.onOpenFullText,
  });

  final ReferenceBookMatch match;
  final VoidCallback? onOpenPdf;
  final VoidCallback onOpenFullText;

  @override
  Widget build(BuildContext context) {
    final hasIndexedText =
        match.fullText.isNotEmpty || match.excerpt.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${match.bookLabel} · p. ${match.page}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (match.fileName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                match.fileName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
              ),
            ],
            if (onOpenPdf != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: onOpenPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                label: Text('Open PDF (page ${match.page})'),
              ),
            ] else if (hasIndexedText) ...[
              const SizedBox(height: 8),
              Text(
                'PDF link unavailable for this hit (rebuild index with manifest URLs).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
              ),
            ],
            if (match.excerpt.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                title: Text(
                  'Excerpt from search index',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                childrenPadding: const EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: 12,
                ),
                children: [
                  SelectionArea(
                    child: _FormattedBookText(match.excerpt),
                  ),
                ],
              ),
            ],
            if (hasIndexedText) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onOpenFullText,
                  icon: const Icon(Icons.article_outlined, size: 18),
                  label: const Text('View full indexed page text'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FormattedBookText extends StatelessWidget {
  const _FormattedBookText(this.raw);

  final String raw;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.42);
    final normalized = raw.replaceAll('\t', '    ');
    final blocks = normalized.split('\n\n');
    if (blocks.length == 1) {
      return Text(blocks[0], style: style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Text(blocks[i], style: style),
        ],
      ],
    );
  }
}

class _ReferenceSearchMetaCard extends StatelessWidget {
  const _ReferenceSearchMetaCard({required this.meta});

  final ReferenceBooksSearchMeta meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How we searched the books',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (meta.seriesFilterApplied && meta.seriesFilterPageTotal > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Corpus: CTC 1, CTC 2, War Machine only '
                '(${meta.seriesFilterPageTotal} indexed pages). '
                '${meta.candidateCount > 0 ? '${meta.candidateCount} candidates scored; ' : ''}'
                '${meta.rerankUsed ? 'Semantic rerank applied.' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
            if (meta.topic.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(meta.topic, style: theme.textTheme.bodyMedium),
            ],
            if (meta.searchPhrases.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in meta.searchPhrases)
                    Chip(
                      label: Text(p, style: theme.textTheme.bodySmall),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
            if (meta.fallbackNote != null &&
                meta.fallbackNote!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                meta.fallbackNote!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
            if (meta.llmError != null && meta.llmError!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                meta.llmError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (meta.rerankNote != null &&
                meta.rerankNote!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                meta.rerankNote!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
            if (meta.rerankError != null &&
                meta.rerankError!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                meta.rerankError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

