import 'package:core_review/utils/explanation_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('partitionExplanation splits Imaging Findings and Discussion', () {
    const raw =
        'A. Lead text. Imaging Findings: Foo bar. Discussion: Baz end.';
    final blocks = partitionExplanation(raw);
    expect(blocks.length, 3);
    expect(blocks[0].header, isNull);
    expect(blocks[0].body, 'A. Lead text.');
    expect(blocks[0].startInRaw, 0);
    expect(blocks[1].header, 'Imaging Findings:');
    expect(blocks[1].body.trim(), 'Foo bar.');
    expect(blocks[2].header?.toLowerCase(), 'discussion:');
    expect(blocks[2].body.trim(), 'Baz end.');
  });

  test('partitionExplanation single block when no headers', () {
    const raw = 'Plain explanation only.';
    final blocks = partitionExplanation(raw);
    expect(blocks.length, 1);
    expect(blocks[0].header, isNull);
    expect(blocks[0].body, raw);
  });
}
