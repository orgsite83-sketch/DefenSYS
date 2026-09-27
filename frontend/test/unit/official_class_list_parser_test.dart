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

    test('correctly parses multi-page USTP List of Enrollment by year level with page intervals', () {
      const ustpCsv = '''LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
,Program,Registered,Officially Enrolled,,,,,,,,
,Bachelor of Science in Information Technology,143,143,,,,,,,,
,TOTAL,,,,,,,,,,
,,143,143,,,,,,,,
LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
Bachelor of Science in Information Technology,,,,,,,,,,,
,#,Student No,Name,Program,Major,Level,,Gender,Status,Date,Date
,1,2024-00001,"DELA CRUZ, Juan",BSIT,,2nd Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,2,2024-00002,"SANTOS, Maria",BSIT,,2nd Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,Print Info:,,,Page 2 of,,,,,,4,
,Monday 22 June 2026,,,,,,,,,,
LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
Bachelor of Science in Information Technology,,,,,,,,,,,
,#,Student No,Name,Program,Major,Level,,Gender,Status,Date,Date
,51,2024-00051,"REYES, Mark",BSIT,,2nd Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,52,2024-00052,"GARCIA, Anna",BSIT,,2nd Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,Print Info:,,,Page 3 of,,,,,,4,
,Monday 22 June 2026,,,,,,,,,,
LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
Bachelor of Science in Information Technology,,,,,,,,,,,
,#,Student No,Name,Program,Major,Level,,Gender,Status,Date,Date
,101,2024-00101,"TORRES, Miguel",BSIT,,2nd Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,TOTAL,,,,143,143,,,,,,
''';

      final result = parseOfficialClassListCsv(ustpCsv);
      expect(result.metadata['school_year'], '2026-2027');
      expect(result.metadata['semester'], '1st Semester');
      expect(result.metadata['year_level'], '2nd Year');
      expect(result.metadata['program'], 'Bachelor of Science in Information Technology');
      expect(result.students.length, 5);

      expect(result.students[0]['id_number'], '2024-00001');
      expect(result.students[0]['first_name'], 'Juan');
      expect(result.students[0]['last_name'], 'DELA CRUZ');
      expect(result.students[0]['year_level'], '2nd Year');
      expect(result.students[0]['email'], '202400001@ustp.edu.ph');
      expect(result.students[0]['gender'], 'M');
      expect(result.students[0]['status'], 'Officially Enrolled');
      expect(result.students[0]['program'], 'BSIT');

      expect(result.students[1]['id_number'], '2024-00002');
      expect(result.students[1]['first_name'], 'Maria');
      expect(result.students[1]['last_name'], 'SANTOS');
      expect(result.students[1]['year_level'], '2nd Year');
      expect(result.students[1]['email'], '202400002@ustp.edu.ph');

      expect(result.students[2]['id_number'], '2024-00051');
      expect(result.students[2]['first_name'], 'Mark');
      expect(result.students[2]['last_name'], 'REYES');
      expect(result.students[2]['year_level'], '2nd Year');
      expect(result.students[2]['email'], '202400051@ustp.edu.ph');

      expect(result.students[3]['id_number'], '2024-00052');
      expect(result.students[3]['first_name'], 'Anna');
      expect(result.students[3]['last_name'], 'GARCIA');
      expect(result.students[3]['year_level'], '2nd Year');

      expect(result.students[4]['id_number'], '2024-00101');
      expect(result.students[4]['first_name'], 'Miguel');
      expect(result.students[4]['last_name'], 'TORRES');
      expect(result.students[4]['year_level'], '2nd Year');
    });
  });
}
