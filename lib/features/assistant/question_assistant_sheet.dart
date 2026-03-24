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
  String? _errorMessage;
  AssistantReply? _explainReply;
  AssistantReply? _customReply;
  List<AssistantWebImage> _webImages = const <AssistantWebImage>[];

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

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final isBusy = _isExplaining || _isAskingCustom;

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
