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
      return;
    }
    if (selection.isCollapsed) {
      _pendingSelection = null;
      return;
    }
    _pendingSelection = selection;
    _debounce = Timer(const Duration(milliseconds: 280), _applyPendingSelection);
  }

  void _applyPendingSelection() {
    if (!mounted) {
      return;
    }
    final sel = _pendingSelection;
    _pendingSelection = null;
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
    required TextStyle baseStyle,
    required Color highlightColor,
  }) {
    if (text.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }
    final sorted = [...highlights]..sort((a, b) => a.start.compareTo(b.start));
    final children = <TextSpan>[];
    var pos = 0;
    final len = text.length;

    for (final h in sorted) {
      if (!h.isValid) {
        continue;
      }
      final hs = h.start.clamp(0, len);
      final he = h.end.clamp(0, len);
      if (he <= hs) {
        continue;
      }
      if (hs > pos) {
        children.add(TextSpan(text: text.substring(pos, hs)));
      }
      children.add(
        TextSpan(
          text: text.substring(hs, he),
          style: baseStyle.copyWith(backgroundColor: highlightColor),
        ),
      );
      pos = he;
      if (pos >= len) {
        break;
      }
    }
    if (pos < len) {
      children.add(TextSpan(text: text.substring(pos)));
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

    // Browser native selection is blocked via user-select:none in index.html;
    // we use Flutter's own selection paint so users see a live drag indicator
    // before the highlight is committed on pointer-up.
    final selectionTint = theme.colorScheme.primary.withValues(alpha: 0.22);

    final richSpan = _buildSpanTree(
      text: widget.text,
      highlights: widget.highlights,
      baseStyle: resolved,
      highlightColor: highlightColor,
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
            selectionColor: selectionTint,
            mouseCursor: SystemMouseCursors.text,
            child: selectable,
          )
        : selectable;
  }
}
