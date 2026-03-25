import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/book_models.dart';
import 'assistant_repository.dart';

class QuestionAssistantSheet extends StatefulWidget {
  const QuestionAssistantSheet({
    required this.question,
    required this.allowAnswerReveal,
    required this.assistantRepository,
    super.key,
  });

  final BookQuestion question;
  final bool allowAnswerReveal;
  final AssistantRepository assistantRepository;

  @override
  State<QuestionAssistantSheet> createState() => _QuestionAssistantSheetState();
}

class _QuestionAssistantSheetState extends State<QuestionAssistantSheet> {
  final TextEditingController _customPromptController = TextEditingController();

  bool _isExplaining = false;
  bool _isAskingCustom = false;
  bool _isSearchingRefBooks = false;
  String? _errorMessage;
  AssistantReply? _explainReply;
  AssistantReply? _customReply;
  List<AssistantWebImage> _webImages = const <AssistantWebImage>[];
  ReferenceBooksSearchResult? _referenceResult;

  @override
  void dispose() {
    _customPromptController.dispose();
    super.dispose();
  }

  String _defaultExplainPrompt() {
    if (widget.allowAnswerReveal) {
      return 'Explain this question clearly for board review. Summarize the key teaching point, '
          'why the correct answer is right, and provide 2–4 short search phrases for representative '
          'radiology images (modality and pathology as appropriate).';
    }
    return 'Explain this question in study mode without naming or ranking the answer choices. '
        'Focus on imaging findings, pathophysiology, and differential clues. Provide 2–4 short '
        'search phrases for representative radiology images.';
  }

  Future<void> _explainWithImages() async {
    setState(() {
      _isExplaining = true;
      _errorMessage = null;
      _explainReply = null;
      _webImages = const <AssistantWebImage>[];
    });

    try {
      final reply = await widget.assistantRepository.askQuestion(
        question: widget.question,
        userPrompt: _defaultExplainPrompt(),
        allowAnswerReveal: widget.allowAnswerReveal,
        includeWebImages: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _explainReply = reply;
        _webImages = reply.webImages;
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
          _isExplaining = false;
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
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString().replaceFirst('Bad state: ', '');
        _referenceResult = null;
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
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final isBusy =
        _isExplaining || _isAskingCustom || _isSearchingRefBooks;

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
            child: FilledButton.icon(
              onPressed: isBusy ? null : _explainWithImages,
              icon: _isExplaining
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lightbulb_outline),
              label: const Text('Explain question + images'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message:
                  'Uses a short model pass to pick topic and search terms, then matches text in your deployed book index.',
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : _searchReferenceBooks,
                icon: _isSearchingRefBooks
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.menu_book_outlined),
                label: const Text('Crack the Core / War Machine pages'),
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
              labelText: 'Your question',
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
                  for (final m in _referenceResult!.matches) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${m.bookLabel} · p. ${m.page}',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (m.fileName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                m.fileName,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                  color: Theme.of(context).hintColor,
                                ),
                              ),
                            ],
                            if (m.excerpt.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SelectionArea(
                                child: _FormattedBookText(m.excerpt),
                              ),
                            ],
                            if (m.fullText.isNotEmpty ||
                                m.excerpt.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _showFullReferencePage(context, m),
                                  icon: const Icon(
                                    Icons.article_outlined,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'View full indexed page',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                ],
                if (_explainReply != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectionArea(
                        child: Text(_explainReply!.answer),
                      ),
                    ),
                  ),
                ],
                if (_webImages.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (final image in _webImages) ...[
                    _WebImageCard(image: image),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            ),
          ),
        ],
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
          ],
        ),
      ),
    );
  }
}

class _WebImageCard extends StatelessWidget {
  const _WebImageCard({required this.image});

  final AssistantWebImage image;

  @override
  Widget build(BuildContext context) {
    final previewUrl = image.thumbnailUrl.isNotEmpty
        ? image.thumbnailUrl
        : image.imageUrl;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image.title.isNotEmpty)
              Text(
                image.title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            if (image.title.isNotEmpty) const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (image.query.isNotEmpty)
                  Chip(label: Text(image.query)),
                if (image.sourceLabel.isNotEmpty)
                  Chip(label: Text(image.sourceLabel)),
              ],
            ),
            if (previewUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: InkWell(
                    onTap: () => _openFullscreenImage(context),
                    borderRadius: BorderRadius.circular(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _NetworkImage(
                        imageUrl: previewUrl,
                        height: 220,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (image.caption.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectionArea(child: Text(image.caption)),
            ],
            if (image.sourceUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Source',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      image.sourceUrl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: image.sourceUrl),
                    ),
                    tooltip: 'Copy source URL',
                    icon: const Icon(Icons.link),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openFullscreenImage(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                image.title.isEmpty ? 'Image' : image.title,
              ),
            ),
            body: InteractiveViewer(
              minScale: 0.75,
              maxScale: 5,
              child: Center(
                child: _NetworkImage(
                  imageUrl: image.imageUrl.isNotEmpty
                      ? image.imageUrl
                      : image.thumbnailUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NetworkImage extends StatelessWidget {
  const _NetworkImage({
    required this.imageUrl,
    this.height,
    this.fit = BoxFit.contain,
  });

  final String imageUrl;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return Image.network(
      imageUrl,
      height: height,
      width: double.infinity,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: height ?? 220,
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Unable to load this web image.'),
          ),
        );
      },
    );
  }
}
