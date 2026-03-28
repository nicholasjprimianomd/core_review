import 'package:flutter/material.dart';

import '../models/text_highlight_utils.dart';
import '../utils/explanation_format.dart';
import 'highlightable_selectable_text.dart';

/// Multi-section explanation with bold headers and per-section highlighting.
class FormattedExplanationSelect extends StatelessWidget {
  const FormattedExplanationSelect({
    required this.fullText,
    required this.baseStyle,
    required this.headerStyle,
    required this.highlights,
    required this.onHighlightsChanged,
    super.key,
  });

  final String fullText;
  final TextStyle? baseStyle;
  final TextStyle? headerStyle;
  final List<TextHighlightSpan> highlights;
  final ValueChanged<List<TextHighlightSpan>> onHighlightsChanged;

  List<TextHighlightSpan> _localHighlightsForBlock(int start, int end) {
    final len = end - start;
    if (len <= 0) {
      return const <TextHighlightSpan>[];
    }
    final out = <TextHighlightSpan>[];
    for (final h in highlights) {
      final hs = h.start.clamp(start, end);
      final he = h.end.clamp(start, end);
      if (he > hs) {
        out.add(TextHighlightSpan(start: hs - start, end: he - start));
      }
    }
    return out;
  }

  void _onBlockChanged(int blockStart, int blockEnd, List<TextHighlightSpan> local) {
    final merged = mergeBlockHighlightsIntoGlobal(
      highlights,
      blockStart,
      blockEnd,
      local,
    );
    onHighlightsChanged(merged);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = baseStyle ?? theme.textTheme.bodyLarge;
    final headStyle = headerStyle ??
        theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);

    final blocks = partitionExplanation(fullText);
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _ExplanationSection(
            block: blocks[i],
            bodyStyle: bodyStyle,
            headerStyle: headStyle,
            localHighlights: _localHighlightsForBlock(
              blocks[i].startInRaw,
              blocks[i].endInRaw,
            ),
            onChanged: (local) => _onBlockChanged(
              blocks[i].startInRaw,
              blocks[i].endInRaw,
              local,
            ),
          ),
        ],
      ],
    );
  }
}

class _ExplanationSection extends StatelessWidget {
  const _ExplanationSection({
    required this.block,
    required this.bodyStyle,
    required this.headerStyle,
    required this.localHighlights,
    required this.onChanged,
  });

  final ExplanationBlock block;
  final TextStyle? bodyStyle;
  final TextStyle? headerStyle;
  final List<TextHighlightSpan> localHighlights;
  final ValueChanged<List<TextHighlightSpan>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (block.header == null) {
      if (block.body.isEmpty) {
        return const SizedBox.shrink();
      }
      return HighlightableSelectableText(
        text: block.body,
        style: bodyStyle,
        highlights: localHighlights,
        onHighlightsChanged: onChanged,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          block.header!,
          style: headerStyle,
        ),
        if (block.body.isNotEmpty) ...[
          const SizedBox(height: 6),
          HighlightableSelectableText(
            text: block.body,
            style: bodyStyle,
            highlights: localHighlights,
            onHighlightsChanged: onChanged,
          ),
        ],
      ],
    );
  }
}

/// Removes highlights overlapping [blockStart, blockEnd), adds [local] mapped into global coords.
List<TextHighlightSpan> mergeBlockHighlightsIntoGlobal(
  List<TextHighlightSpan> global,
  int blockStart,
  int blockEnd,
  List<TextHighlightSpan> local,
) {
  final trimmed = <TextHighlightSpan>[];
  for (final h in global) {
    if (h.end <= blockStart || h.start >= blockEnd) {
      trimmed.add(h);
      continue;
    }
    if (h.start < blockStart) {
      trimmed.add(TextHighlightSpan(start: h.start, end: blockStart));
    }
    if (h.end > blockEnd) {
      trimmed.add(TextHighlightSpan(start: blockEnd, end: h.end));
    }
  }

  final mapped = <TextHighlightSpan>[
    for (final h in local)
      if (h.isValid)
        TextHighlightSpan(
          start: blockStart + h.start,
          end: blockStart + h.end,
        ),
  ];

  return normalizeHighlightSpans([...trimmed, ...mapped]);
}
