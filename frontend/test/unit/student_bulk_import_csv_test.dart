import 'package:flutter_test/flutter_test.dart';
import 'package:user/utils/student_bulk_import_csv.dart';

void main() {
  test('each year level sample has four students', () {
    for (final year in studentSampleYearLevels) {
      final lines = sampleStudentCsvForYear(
        year,
      ).split('\n').where((line) => line.trim().isNotEmpty).toList();
      expect(lines.first, 'OFFICIAL LIST OF ENROLLED STUDENTS');
      expect(lines, contains('Year Level,$year'));
      expect(
        lines,
        contains(
          '#,Student Number,Full Name,Program,Gender,Level,OR No.,Validation Date,Email,Contact',
        ),
      );
      expect(
        lines
            .where(
              (line) =>
                  RegExp(r'^\d+,').hasMatch(line) &&
                  line.contains('@ustp.edu.ph'),
            )
            .length,
        4,
        reason: year,
      );
    }
  });
}
