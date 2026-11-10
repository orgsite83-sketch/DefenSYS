import 'package:defensys/utils/rubric_weight_allocation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('even shares total 100% and differ by at most 0.01%', () {
    for (final count in [
      ...List<int>.generate(200, (i) => i + 1),
      9999,
      10000,
    ]) {
      final shares = allocateRubricWeight(10000, List<int>.filled(count, 1));
      expect(shares.reduce((a, b) => a + b), 10000, reason: '$count items');
      expect(
        shares.every((share) => share > 0),
        isTrue,
        reason: '$count items',
      );
      expect(
        shares.toSet().reduce((a, b) => a > b ? a : b) -
            shares.toSet().reduce((a, b) => a < b ? a : b),
        lessThanOrEqualTo(1),
      );
    }
    expect(allocateRubricWeight(10000, [1, 1, 1]), [3334, 3333, 3333]);
  });

  test(
    'weighted criteria preserve each section budget at two decimal places',
    () {
      for (final budget in [1, 7, 3333, 3334, 10000]) {
        for (var count = 1; count <= 100; count++) {
          final points = List<int>.generate(
            count,
            (i) => (i * 17 + count) % 32767 + 1,
          );
          final shares = allocateRubricWeight(budget, points);
          final totalPoints = points.reduce((a, b) => a + b);
          expect(shares.reduce((a, b) => a + b), budget);
          for (var i = 0; i < count; i++) {
            expect(
              (shares[i] - budget * points[i] / totalPoints).abs(),
              lessThan(1),
            );
          }
        }
      }
      expect(allocateRubricWeight(3334, [1, 1, 1]), [1112, 1111, 1111]);
      expect(allocateRubricWeight(3333, [1, 2, 4]), [476, 952, 1905]);
    },
  );

  test('empty and incomplete sections are deterministic', () {
    expect(allocateRubricWeight(10000, []), isEmpty);
    expect(allocateRubricWeight(0, [1, 2]), [0, 0]);
    expect(allocateRubricWeight(10000, [0, 0, 0]), [3334, 3333, 3333]);
    expect(allocateRubricWeight(10000, [0, 10]), [0, 10000]);
    expect(() => allocateRubricWeight(10000, [-1, 10]), throwsArgumentError);
  });

  test(
    'percentage text round-trips every hundredth without excess decimals',
    () {
      for (var value = 0; value <= 10000; value++) {
        final text = formatRubricWeight(value);
        expect((num.parse(text) * 100).round(), value);
        expect(text, matches(RegExp(r'^\d+(\.\d{1,2})?$')));
      }
      expect(formatRubricWeight(10000), '100');
      expect(formatRubricWeight(3334), '33.34');
      expect(formatRubricWeight(10), '0.1');
      expect(formatRubricWeight(1), '0.01');
    },
  );
}
