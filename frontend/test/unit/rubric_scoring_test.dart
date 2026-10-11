import 'package:defensys/utils/rubric_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unequal rubric weights normalize mixed score scales', () {
    expect(rubricPercentage([const RubricScore(9, 10, 80), const RubricScore(2.5, 5, 20)]), 82);
  });
  test('five criteria and decimal allocations preserve their distributions', () {
    expect(rubricPercentage([
      const RubricScore(9, 10, 40), const RubricScore(2.5, 5, 20),
      const RubricScore(10, 20, 15), const RubricScore(80, 100, 15),
      const RubricScore(10, 10, 10),
    ]), 75.5);
    expect(rubricPercentage([
      const RubricScore(10, 10, 33.33), const RubricScore(5, 10, 33.33),
      const RubricScore(0, 10, 33.34),
    ]), 50);
  });
  test('shared team criteria are combined separately for each student', () {
    const shared = RubricScore(9, 10, 80);
    final first = rubricPercentage([shared, const RubricScore(2.5, 5, 20)])!;
    final second = rubricPercentage([shared, const RubricScore(5, 5, 20)])!;
    expect(first, 82);
    expect(second, 92);
    expect((first + second) / 2, 87);
  });
  test('recorded null weights retain legacy totals; zero is a valid score', () {
    expect(rubricPercentage([const RubricScore(9, 10, null), const RubricScore(2.5, 5, null)]), 76.67);
    expect(rubricPercentage([const RubricScore(0, 10, 100)]), 0);
    expect(rubricPercentage([const RubricScore(5, 0, 100)]), isNull);
  });
  test('recorded panel score comes from the backend response', () {
    final grade = {'panel_evaluation_scores': [
      {'panelist_key': 'teacher', 'student_id': 1, 'percentage': '82.00'},
      {'panelist_key': 'teacher', 'student_id': 2, 'percentage': '92.00'},
    ]};
    expect(recordedPanelPercentage(grade, 'teacher', 1), 82);
    expect(recordedPanelPercentage(grade, 'teacher', 2), 92);
    expect(recordedPanelPercentage(grade, 'other', 1), isNull);
    expect(rubricWeight('33.33'), 33.33);
  });
}
