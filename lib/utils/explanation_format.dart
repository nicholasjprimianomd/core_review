/// Splits book-style explanations into labeled sections (e.g. Imaging Findings, Discussion).
class ExplanationBlock {
  const ExplanationBlock({
    required this.header,
    required this.body,
    required this.startInRaw,
    required this.endInRaw,
  });

  /// Section title including trailing colon, or null for lead-in text before the first header.
  final String? header;

  /// Body text for this block (no header); substring of the original explanation.
  final String body;

  /// Inclusive start index of [body] in the original explanation string.
  final int startInRaw;

  /// Exclusive end index of [body] in the original explanation string.
  final int endInRaw;
}

/// Headers commonly used in neuroradiology / Core Review explanations.
final RegExp _explanationSectionBoundary = RegExp(
  r'\s*((?:Imaging Findings|Discussion|Differential Diagnosis|Differential considerations|Clinical (?:presentation|features)|Pathophysiology|Key points?|Pearls?)\s*:)\s*',
  caseSensitive: false,
);

/// Partitions [raw] into blocks. Indices match [raw] so highlights can be mapped.
List<ExplanationBlock> partitionExplanation(String raw) {
  if (raw.isEmpty) {
    return const <ExplanationBlock>[];
  }
  final matches = _explanationSectionBoundary.allMatches(raw).toList();
  if (matches.isEmpty) {
    return [
      ExplanationBlock(
        header: null,
        body: raw,
        startInRaw: 0,
        endInRaw: raw.length,
      ),
    ];
  }

  final blocks = <ExplanationBlock>[];
  var cursor = 0;

  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    if (m.start > cursor) {
      final lead = raw.substring(cursor, m.start);
      if (lead.isNotEmpty) {
        blocks.add(
          ExplanationBlock(
            header: null,
            body: lead,
            startInRaw: cursor,
            endInRaw: m.start,
          ),
        );
      }
    }
    final header = m.group(1)!.trim();
    final bodyEnd =
        i + 1 < matches.length ? matches[i + 1].start : raw.length;
    final body = raw.substring(m.end, bodyEnd);
    blocks.add(
      ExplanationBlock(
        header: header,
        body: body,
        startInRaw: m.end,
        endInRaw: bodyEnd,
      ),
    );
    cursor = bodyEnd;
  }

  if (blocks.isEmpty) {
    return [
      ExplanationBlock(
        header: null,
        body: raw,
        startInRaw: 0,
        endInRaw: raw.length,
      ),
    ];
  }

  return blocks;
}
