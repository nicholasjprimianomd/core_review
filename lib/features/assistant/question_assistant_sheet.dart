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
  final TextEditingController _promptController = TextEditingController();

  bool _isAskingAssistant = false;
  bool _isLoadingWebImages = false;
  bool _hasRequestedWebImages = false;
  String? _errorMessage;
  String? _lastSubmittedPrompt;
  AssistantReply? _reply;
  List<AssistantWebImage> _webImages = const <AssistantWebImage>[];

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final question = widget.question;
    final isBusy = _isAskingAssistant || _isLoadingWebImages;
    final webImages = _webImages;
    final canShowWebImages =
        _isAskingAssistant ||
        _isLoadingWebImages ||
        _hasRequestedWebImages ||
        _reply != null ||
        _webImages.isNotEmpty;

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
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.allowAnswerReveal
                  ? 'The assistant uses only this question and your prompt. It does not search through the rest of the textbook. Ask AI to get a quick explanation plus relevant pathology images from the web.'
                  : 'The assistant uses only this question and your prompt. It does not search through the rest of the textbook. Before you submit an answer, it stays in hint mode while still pulling relevant pathology images from the web.',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickPromptChip(
                label: 'Explain this question',
                enabled: !isBusy,
                onTap: () => _useQuickPrompt(
                  'Explain the core teaching point of this question in plain language.',
                ),
              ),
              _QuickPromptChip(
                label: 'Differential clues',
                enabled: !isBusy,
                onTap: () => _useQuickPrompt(
                  'What imaging clues help narrow the differential diagnosis for this question?',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _promptController,
            minLines: 3,
            maxLines: 6,
            textInputAction: TextInputAction.send,
            decoration: InputDecoration(
              labelText: 'Ask for a deeper explanation',
              hintText:
                  'Example: Explain the main teaching point and the differential clues for this question.',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: isBusy ? null : _askAssistant,
                tooltip: 'Ask AI',
                icon: const Icon(Icons.keyboard_return),
              ),
            ),
            onSubmitted: isBusy ? null : (_) => _askAssistant(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              question.hasImages
                  ? 'This question already has ${question.imageAssets.length} textbook image${question.imageAssets.length == 1 ? '' : 's'} above. Ask AI to explain the question and pull matching web examples for comparison.'
                  : 'Ask AI to explain the question and pull matching web examples that make the pathology easier to recognize.',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: isBusy ? null : _askAssistant,
                icon: _isAskingAssistant
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: const Text('Ask AI + Web Images'),
              ),
              OutlinedButton.icon(
                onPressed: isBusy ? null : _showWebExamples,
                icon: _isLoadingWebImages
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_search_outlined),
                label: const Text('Refresh Web Images'),
              ),
            ],
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
                if (_reply != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectionArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Assistant response',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            Text(_reply!.answer),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_reply!.searchTerms.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Web image search terms',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _reply!.searchTerms
                          .map((term) => Chip(label: Text(term)))
                          .toList(growable: false),
                    ),
                  ],
                ],
                if (canShowWebImages) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Example images from the web',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_isAskingAssistant || _isLoadingWebImages)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    )
                  else if (webImages.isEmpty)
                    const Text(
                      'No open-access web image matches were found for this query. Try a more specific pathology or imaging pattern.',
                    )
                  else
                    for (final image in webImages) ...[
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

  Future<void> _askAssistant() async {
    final userPrompt = _promptController.text.trim();
    if (userPrompt.isEmpty) {
      setState(() {
        _errorMessage = 'Enter a question for the assistant first.';
      });
      return;
    }

    setState(() {
      _isAskingAssistant = true;
      _errorMessage = null;
      _hasRequestedWebImages = true;
      _reply = null;
      _webImages = const <AssistantWebImage>[];
    });

    try {
      final reply = await widget.assistantRepository.askQuestion(
        question: widget.question,
        userPrompt: userPrompt,
        allowAnswerReveal: widget.allowAnswerReveal,
        includeWebImages: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _reply = reply;
        _lastSubmittedPrompt = userPrompt;
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
          _isAskingAssistant = false;
        });
      }
    }
  }

  Future<void> _showWebExamples() async {
    final currentPrompt = _promptController.text.trim();
    final userPrompt = currentPrompt.isNotEmpty
        ? currentPrompt
        : (_lastSubmittedPrompt ?? _defaultWebExamplesPrompt());
    final canReuseSearchTerms =
        _reply != null &&
        _reply!.searchTerms.isNotEmpty &&
        _lastSubmittedPrompt == userPrompt;

    setState(() {
      _isLoadingWebImages = true;
      _hasRequestedWebImages = true;
      _errorMessage = null;
    });

    try {
      final reply = await widget.assistantRepository.askQuestion(
        question: widget.question,
        userPrompt: userPrompt,
        allowAnswerReveal: widget.allowAnswerReveal,
        includeAnswer: !canReuseSearchTerms,
        includeWebImages: true,
        searchTerms: canReuseSearchTerms
            ? _reply!.searchTerms
            : const <String>[],
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (!canReuseSearchTerms) {
          _reply = reply;
        }
        _lastSubmittedPrompt = userPrompt;
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
          _isLoadingWebImages = false;
        });
      }
    }
  }

  void _useQuickPrompt(String prompt) {
    _promptController.text = prompt;
    _promptController.selection = TextSelection.collapsed(
      offset: _promptController.text.length,
    );
    _askAssistant();
  }

  String _defaultWebExamplesPrompt() {
    if (widget.allowAnswerReveal) {
      return 'Explain this question and show relevant pathology images from the web.';
    }
    return 'Help me study this question in hint mode and show relevant pathology images from the web without revealing the correct answer.';
  }
}

class _QuickPromptChip extends StatelessWidget {
  const _QuickPromptChip({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.auto_awesome_outlined, size: 18),
      label: Text(label),
      onPressed: enabled ? onTap : null,
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
            Text(
              image.title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (image.query.isNotEmpty)
                  Chip(label: Text('Search: ${image.query}')),
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
                image.title.isEmpty ? 'Web pathology example' : image.title,
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
