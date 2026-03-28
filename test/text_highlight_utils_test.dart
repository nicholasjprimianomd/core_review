import 'package:core_review/models/text_highlight_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toggleHighlightSelection', () {
    test('adds highlight when selection does not overlap', () {
      final next = toggleHighlightSelection(const [], 2, 5, '0123456789'.length);
      expect(next, const [TextHighlightSpan(start: 2, end: 5)]);
    });

    test('removes overlapping slice only', () {
      const current = [TextHighlightSpan(start: 0, end: 10)];
      final next = toggleHighlightSelection(current, 3, 7, 12);
      expect(
        next,
        const [
          TextHighlightSpan(start: 0, end: 3),
          TextHighlightSpan(start: 7, end: 10),
        ],
      );
    });

    test('removes full highlight when selection covers it', () {
      const current = [TextHighlightSpan(start: 2, end: 5)];
      final next = toggleHighlightSelection(current, 2, 5, 10);
      expect(next, isEmpty);
    });

    test('merges adjacent added spans', () {
      final a = toggleHighlightSelection(const [], 0, 2, 10);
      final b = toggleHighlightSelection(a, 2, 4, 10);
      expect(b, const [TextHighlightSpan(start: 0, end: 4)]);
    });
  });
}
