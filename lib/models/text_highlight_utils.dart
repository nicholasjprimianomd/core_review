/// Stored highlight range in [start, end) (Dart string indices / UTF-16 code units).
class TextHighlightSpan {
  const TextHighlightSpan({required this.start, required this.end});

  final int start;
  final int end;

  bool get isValid => end > start && start >= 0;

  @override
  bool operator ==(Object other) =>
      other is TextHighlightSpan &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'start': start,
    'end': end,
  };

  factory TextHighlightSpan.fromJson(Map<String, dynamic> json) {
    return TextHighlightSpan(
      start: json['start'] as int,
      end: json['end'] as int,
    );
  }
}

/// Returns sorted, merged, non-overlapping highlight spans.
List<TextHighlightSpan> normalizeHighlightSpans(List<TextHighlightSpan> input) {
  final filtered = input.where((h) => h.isValid).toList()
    ..sort((a, b) {
      final c = a.start.compareTo(b.start);
      if (c != 0) {
        return c;
      }
      return a.end.compareTo(b.end);
    });
  if (filtered.isEmpty) {
    return const <TextHighlightSpan>[];
  }
  final out = <TextHighlightSpan>[filtered.first];
  for (var i = 1; i < filtered.length; i++) {
    final cur = filtered[i];
    final last = out.last;
    if (cur.start <= last.end) {
      out[out.length - 1] = TextHighlightSpan(
        start: last.start,
        end: cur.end > last.end ? cur.end : last.end,
      );
    } else {
      out.add(cur);
    }
  }
  return List.unmodifiable(out);
}

/// If [sel] overlaps any highlight, those spans are trimmed / split so the
/// overlap is removed. If [sel] hits nothing highlighted, it is added as new.
///
/// Returns a new list (normalized). Equal ranges mean no change.
List<TextHighlightSpan> toggleHighlightSelection(
  List<TextHighlightSpan> current,
  int selStart,
  int selEnd,
  int textLength,
) {
  final len = textLength < 0 ? 0 : textLength;
  var s = selStart.clamp(0, len);
  var e = selEnd.clamp(0, len);
  if (s > e) {
    final t = s;
    s = e;
    e = t;
  }
  if (e <= s) {
    return current;
  }

  var removedAny = false;
  final remnants = <TextHighlightSpan>[];
  for (final h in current) {
    if (!h.isValid || h.end <= s || h.start >= e) {
      remnants.add(h);
      continue;
    }
    removedAny = true;
    if (h.start < s) {
      remnants.add(TextHighlightSpan(start: h.start, end: s));
    }
    if (e < h.end) {
      remnants.add(TextHighlightSpan(start: e, end: h.end));
    }
  }

  if (!removedAny) {
    remnants.add(TextHighlightSpan(start: s, end: e));
  }

  return normalizeHighlightSpans(remnants);
}

List<TextHighlightSpan> textHighlightSpansFromJson(List<dynamic>? raw) {
  if (raw == null || raw.isEmpty) {
    return const <TextHighlightSpan>[];
  }
  final out = <TextHighlightSpan>[];
  for (final item in raw) {
    final m = item as Map<String, dynamic>;
    final span = TextHighlightSpan.fromJson(m);
    if (span.isValid) {
      out.add(span);
    }
  }
  return normalizeHighlightSpans(out);
}
