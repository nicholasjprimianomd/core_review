import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/text_highlight_utils.dart';

/// Selectable text with click-drag highlights (toggle: select again to clear).
class HighlightableSelectableText extends StatefulWidget {
  const HighlightableSelectableText({
    super.key,
    required this.text,
    required this.style,
    required this.highlights,
    required this.onHighlightsChanged,
  });

  final String text;
  final TextStyle? style;
  final List<TextHighlightSpan> highlights;
  final ValueChanged<List<TextHighlightSpan>> onHighlightsChanged;

  @override
  State<HighlightableSelectableText> createState() =>
      _HighlightableSelectableTextState();
}

class _HighlightableSelectableTextState extends State<HighlightableSelectableText> {
  Timer? _debounce;
  TextSelection? _pendingSelection;
  // Live extent of the user's in-progress drag, painted as an extra background
  // span layer so the drag is visible even on web where Flutter's built-in
  // selection paint is unreliable behind `user-select: none`.
  TextSelection? _liveDragSelection;

  /// On web, [SelectableText] can keep an internal selection across rebuilds; after we merge
  /// the drag into [TextSpan] backgrounds the span tree changes but the selection rect may
  /// not be recomputed, leaving a shifted blue "ghost" slice. Forcing a new element clears it.
  int _selectableIdentity(String text, List<TextHighlightSpan> highlights) {
    var h = 0;
    for (final s in highlights) {
      h = Object.hash(h, s.start);
      h = Object.hash(h, s.end);
    }
    return Object.hash(text.hashCode, h);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    _debounce?.cancel();
    if (cause == SelectionChangedCause.toolbar) {
      _pendingSelection = null;
      _setLiveDrag(null);
      return;
    }
    if (selection.isCollapsed) {
      _pendingSelection = null;
      _setLiveDrag(null);
      return;
    }
    _pendingSelection = selection;
    _setLiveDrag(selection);
    _debounce = Timer(const Duration(milliseconds: 280), _applyPendingSelection);
  }

  void _setLiveDrag(TextSelection? selection) {
    final next = (selection == null || selection.isCollapsed) ? null : selection;
    final cur = _liveDragSelection;
    final same = cur == null
        ? next == null
        : (next != null && cur.start == next.start && cur.end == next.end);
    if (same) {
      return;
    }
    setState(() => _liveDragSelection = next);
  }

  void _applyPendingSelection() {
    if (!mounted) {
      return;
    }
    final sel = _pendingSelection;
    _pendingSelection = null;
    _setLiveDrag(null);
    if (sel == null || sel.isCollapsed) {
      return;
    }
    final next = toggleHighlightSelection(
      widget.highlights,
      sel.baseOffset,
      sel.extentOffset,
      widget.text.length,
    );
    if (listEquals(next, widget.highlights)) {
      return;
    }
    widget.onHighlightsChanged(next);
  }

  static TextSpan _buildSpanTree({
    required String text,
    required List<TextHighlightSpan> highlights,
    required TextSelection? dragSelection,
    required TextStyle baseStyle,
    required Color highlightColor,
    required Color dragPreviewColor,
  }) {
    if (text.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }
    final len = text.length;

    final dragStart = dragSelection != null && !dragSelection.isCollapsed
        ? dragSelection.start.clamp(0, len)
        : -1;
    final dragEnd = dragSelection != null && !dragSelection.isCollapsed
        ? dragSelection.end.clamp(0, len)
        : -1;
    final hasDrag = dragStart >= 0 && dragEnd > dragStart;

    final breakpoints = <int>{0, len};
    final sortedHighlights = <TextHighlightSpan>[];
    for (final h in highlights) {
      if (!h.isValid) {
        continue;
      }
      final hs = h.start.clamp(0, len);
      final he = h.end.clamp(0, len);
      if (he <= hs) {
        continue;
      }
      sortedHighlights.add(TextHighlightSpan(start: hs, end: he));
      breakpoints.add(hs);
      breakpoints.add(he);
    }
    if (hasDrag) {
      breakpoints.add(dragStart);
      breakpoints.add(dragEnd);
    }
    final cuts = breakpoints.toList()..sort();

    Color? colorAt(int pos) {
      if (hasDrag && pos >= dragStart && pos < dragEnd) {
        return dragPreviewColor;
      }
      for (final h in sortedHighlights) {
        if (pos >= h.start && pos < h.end) {
          return highlightColor;
        }
      }
      return null;
    }

    final children = <TextSpan>[];
    for (var i = 0; i < cuts.length - 1; i++) {
      final start = cuts[i];
      final end = cuts[i + 1];
      if (start >= end) {
        continue;
      }
      final color = colorAt(start);
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: color != null
              ? baseStyle.copyWith(backgroundColor: color)
              : null,
        ),
      );
    }

    if (children.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }
    return TextSpan(style: baseStyle, children: children);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeBody = theme.textTheme.bodyLarge ?? const TextStyle();
    final resolved = widget.style ?? themeBody;

    final highlightColor = theme.brightness == Brightness.dark
        ? const Color(0xFF8B6914).withValues(alpha: 0.65)
        : const Color(0xFFFFF176).withValues(alpha: 0.85);

    // Live drag preview color (distinct from the committed yellow highlight
    // so the user can tell pre-commit selection apart from the final mark).
    final dragPreviewColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.primary.withValues(alpha: 0.45)
        : theme.colorScheme.primary.withValues(alpha: 0.30);

    // Flutter's built-in selection paint is unreliable on web behind
    // `user-select: none`; we render our own drag preview as a [TextSpan]
    // background instead, so suppress the framework tint on web to avoid
    // the misaligned "ghost" rect.
    final selectionTint = kIsWeb
        ? Colors.transparent
        : theme.colorScheme.primary.withValues(alpha: 0.22);

    final richSpan = _buildSpanTree(
      text: widget.text,
      highlights: widget.highlights,
      dragSelection: _liveDragSelection,
      baseStyle: resolved,
      highlightColor: highlightColor,
      dragPreviewColor: dragPreviewColor,
    );
    final strut = StrutStyle.fromTextStyle(
      resolved,
      forceStrutHeight: true,
    );

    final selectable = SelectableText.rich(
      key: ValueKey<int>(
        _selectableIdentity(widget.text, widget.highlights),
      ),
      richSpan,
      strutStyle: strut,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
      ),
      selectionColor: selectionTint,
      magnifierConfiguration: kIsWeb ? TextMagnifierConfiguration.disabled : null,
      contextMenuBuilder: (context, editableTextState) {
        final items = List<ContextMenuButtonItem>.from(
          editableTextState.contextMenuButtonItems,
        );
        if (widget.highlights.isNotEmpty) {
          items.add(
            ContextMenuButtonItem(
              label: 'Copy highlights',
              onPressed: () {
                ContextMenuController.removeAny();
                final t = mergedHighlightedText(widget.text, widget.highlights);
                unawaited(Clipboard.setData(ClipboardData(text: t)));
                if (editableTextState.mounted) {
                  editableTextState.hideToolbar();
                }
              },
            ),
          );
        }
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: items,
        );
      },
      onSelectionChanged: _onSelectionChanged,
    );

    return kIsWeb
        ? DefaultSelectionStyle.merge(
            selectionColor: Colors.transparent,
            mouseCursor: SystemMouseCursors.text,
            child: selectable,
          )
        : selectable;
  }
}
