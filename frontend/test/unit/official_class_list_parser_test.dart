import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/user_management/bulk_import/official_class_list_parser.dart';

void main() {
  group('parseOfficialClassListCsv', () {
    test('does not misparse standard faculty CSV columns as metadata', () {
      const facultyCsv = '''id_number,first_name,last_name,email,role,year_level,section,faculty
206,Ricardo,Fontanilla,206@ustp.edu.ph,faculty,,,
207,Maricel,Suarez,207@ustp.edu.ph,faculty,,,
''';

      final result = parseOfficialClassListCsv(facultyCsv);
      expect(result.students, isEmpty);
      expect(result.metadata.containsKey('year_level'), isFalse);
      expect(result.metadata.containsKey('section'), isFalse);
      expect(result.metadata.containsKey('faculty'), isFalse);
    });

    test('correctly parses USTP Official Class List format with metadata and students', () {
      const officialCsv = '''OFFICIAL LIST OF ENROLLED STUDENTS
S.Y. 2025-2026, 1st Sem
Subject Code, IT312
Subject Title, Capstone Project 1
Class Section, 3A
Year Level, 3rd Year
Instructor, Dr. Juan Dela Cruz

#,Student Number,Full Name,Email,Contact
1,2022300001,"Dela Cruz, Juan",juan@ustp.edu.ph,09170001011
2,2022300002,"Santos, Maria",maria@ustp.edu.ph,09170001012
''';

      final result = parseOfficialClassListCsv(officialCsv);
      expect(result.metadata['school_year'], '2025-2026');
      expect(result.metadata['semester'], '1st Semester');
      expect(result.metadata['section'], '3A');
      expect(result.metadata['year_level'], '3rd Year');
      expect(result.metadata['faculty'], 'Dr. Juan Dela Cruz');
      expect(result.students.length, 2);
      expect(result.students[0]['id_number'], '2022300001');
      expect(result.students[0]['first_name'], 'Juan');
      expect(result.students[0]['last_name'], 'Dela Cruz');
      expect(result.students[0]['phone_number'], '09170001011');
      expect(result.students[0]['contact'], '09170001011');
      expect(result.students[0]['role'], 'student');
      expect(result.students[0]['section'], '3A');
      expect(result.students[0]['year_level'], '3rd Year');
      expect(result.students[1]['phone_number'], '09170001012');
    });
  });
}
