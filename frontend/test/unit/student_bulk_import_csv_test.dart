import 'package:flutter_test/flutter_test.dart';
import 'package:user/utils/student_bulk_import_csv.dart';

void main() {
  test('each year level sample has four students', () {
    for (final year in studentSampleYearLevels) {
      final lines = sampleStudentCsvForYear(year)
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      expect(lines.first, studentBulkImportHeader);
      expect(lines.length, 5, reason: year);
    }
  });
}
