import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/widgets/file_import_staging_modal.dart';
import 'package:defensys/utils/csv_file_io.dart';

void main() {
  group('FileImportStagingModal Widget Tests', () {
    const facultyCsv = '''id_number,first_name,last_name,email,role
206,Ricardo,Fontanilla,206@ustp.edu.ph,faculty
207,Maricel,Suarez,207@ustp.edu.ph,faculty
208,Jonathan,Beltran,208@ustp.edu.ph,faculty
209,Analiza,Corpuz,209@ustp.edu.ph,faculty
210,Renato,Villanueva,210@ustp.edu.ph,faculty
211,Cecilia,Magbanua,211@ustp.edu.ph,faculty
212,Eduardo,Padilla,212@ustp.edu.ph,faculty
213,Florencia,Dela Torre,213@ustp.edu.ph,faculty
214,Arsenio,Macasaet,214@ustp.edu.ph,faculty
215,Teresita,Buenaventura,215@ustp.edu.ph,faculty
''';

    final facultyFile = PickedTabularFile(
      name: 'demo_faculty_import.csv',
      extension: 'csv',
      bytes: Uint8List.fromList(facultyCsv.codeUnits),
      text: facultyCsv,
    );

    const studentCsv = '''Subject Code,IT311
Class Section,BSIT-3A
Year Level,3rd Year
Instructor,Prof. Alan Turing

Student Number,Full Name,Email,Year Level
20230001,"SMITH, John",john.smith@ustp.edu.ph,3rd Year
20230002,"DOE, Jane",jane.doe@ustp.edu.ph,3rd Year
''';

    final studentFile = PickedTabularFile(
      name: 'bsit_3a_enrolled.csv',
      extension: 'csv',
      bytes: Uint8List.fromList(studentCsv.codeUnits),
      text: studentCsv,
    );

    testWidgets('recognizes faculty CSV in general mode, shows 10 faculty badge and generates preview', (tester) async {
      StagedImportResult? capturedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  capturedResult = await showFileImportStagingModal(
                    context,
                    initialFiles: [facultyFile],
                    importMode: 'general',
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Staged Import Files'), findsOneWidget);
      expect(find.textContaining('Faculty / General Users'), findsOneWidget);
      expect(find.textContaining('Faculty Accounts CSV'), findsOneWidget);
      expect(find.textContaining('10 faculty'), findsOneWidget);
      expect(find.text('Role: Faculty'), findsOneWidget);
      expect(find.text('Add another faculty/staff file'), findsOneWidget);

      // Confirm generate preview button
      await tester.tap(find.text('Generate Preview Table (10 rows)'));
      await tester.pumpAndSettle();

      expect(capturedResult, isNotNull);
      expect(capturedResult!.importMode, 'general');
      expect(capturedResult!.files.length, 1);
    });

    testWidgets('rejects student class list in general (faculty) mode as incompatible', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await showFileImportStagingModal(
                    context,
                    initialFiles: [studentFile],
                    importMode: 'general',
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Staged Import Files'), findsOneWidget);
      expect(find.textContaining('No valid faculty & staff files detected'), findsOneWidget);
      expect(find.textContaining('Official Class List (Student)'), findsOneWidget);
      expect(find.textContaining('Incompatible Format (0 faculty records)'), findsOneWidget);
      expect(find.textContaining('This file is a Student Class List'), findsOneWidget);
      expect(find.text('Generate Preview Table'), findsOneWidget);
    });

    testWidgets('recognizes official student class list in student mode, sets mode to Student Batch and shows section & year badges', (tester) async {
      StagedImportResult? capturedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  capturedResult = await showFileImportStagingModal(
                    context,
                    initialFiles: [studentFile],
                    importMode: 'student',
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Staged Import Files'), findsOneWidget);
      expect(find.textContaining('Student Batch'), findsOneWidget);
      expect(find.textContaining('Official Class List'), findsOneWidget);
      expect(find.text('Section: BSIT-3A'), findsOneWidget);
      expect(find.text('3rd Year'), findsOneWidget);
      expect(find.text('IT311'), findsOneWidget);
      expect(find.text('2 students'), findsOneWidget);
      expect(find.text('Add another class section or file'), findsOneWidget);

      // Confirm generate preview button
      await tester.tap(find.text('Generate Preview Table (2 rows)'));
      await tester.pumpAndSettle();

      expect(capturedResult, isNotNull);
      expect(capturedResult!.importMode, 'student');
      expect(capturedResult!.files.length, 1);
    });

    testWidgets('rejects faculty template in student mode as incompatible', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await showFileImportStagingModal(
                    context,
                    initialFiles: [facultyFile],
                    importMode: 'student',
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Staged Import Files'), findsOneWidget);
      expect(find.textContaining('Faculty Accounts CSV'), findsOneWidget);
      expect(find.textContaining('Incompatible Format (0 student records)'), findsOneWidget);
      expect(find.textContaining('This file is a Faculty & Staff template'), findsOneWidget);
    });

    testWidgets('marks non-student CSVs as incompatible, excludes them from valid counts and skips them on proceed', (tester) async {
      StagedImportResult? capturedResult;

      const scheduleCsv = '''defense_date,room,panelist,time_slot
2026-09-01,Lab 1,Dr. Garcia,09:00 AM
2026-09-01,Lab 2,Dr. Ramos,10:30 AM
''';

      final scheduleFile = PickedTabularFile(
        name: 'defense_schedule_import.csv',
        extension: 'csv',
        bytes: Uint8List.fromList(scheduleCsv.codeUnits),
        text: scheduleCsv,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  capturedResult = await showFileImportStagingModal(
                    context,
                    initialFiles: [studentFile, scheduleFile],
                    importMode: 'student',
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Staged Import Files'), findsOneWidget);
      expect(find.textContaining('1 valid file staged'), findsOneWidget);
      expect(find.textContaining('1 incompatible file will be skipped'), findsOneWidget);
      expect(find.textContaining('Incompatible Format'), findsOneWidget);
      expect(find.textContaining('defense schedule file'), findsOneWidget);

      // Confirm generate preview button only proceeds with the 1 valid file
      await tester.tap(find.text('Generate Preview Table (2 rows)'));
      await tester.pumpAndSettle();

      expect(capturedResult, isNotNull);
      expect(capturedResult!.files.length, 1);
      expect(capturedResult!.files.first.name, 'bsit_3a_enrolled.csv');
    });

    testWidgets('Cancel button dismisses modal and returns null', (tester) async {
      StagedImportResult? capturedResult = const StagedImportResult(files: [], importMode: 'none');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  capturedResult = await showFileImportStagingModal(
                    context,
                    initialFiles: [facultyFile],
                    importMode: 'general',
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Staged Import Files'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Staged Import Files'), findsNothing);
      expect(capturedResult, isNull);
    });

    testWidgets('Close (X) button dismisses modal and returns null', (tester) async {
      StagedImportResult? capturedResult = const StagedImportResult(files: [], importMode: 'none');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  capturedResult = await showFileImportStagingModal(
                    context,
                    initialFiles: [facultyFile],
                    importMode: 'general',
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Staged Import Files'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Staged Import Files'), findsNothing);
      expect(capturedResult, isNull);
    });

    testWidgets('blocks student import and disables preview button when hasActiveSemester is false', (tester) async {
      StagedImportResult? capturedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  capturedResult = await showFileImportStagingModal(
                    context,
                    initialFiles: [studentFile],
                    importMode: 'student',
                    hasActiveSemester: false,
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Staged Import Files'), findsOneWidget);
      expect(find.textContaining('Active Semester Required'), findsWidgets);
      expect(find.text('Active Semester Required'), findsOneWidget);

      // Button is disabled, tapping should not dismiss modal or return result
      await tester.tap(find.text('Active Semester Required'));
      await tester.pumpAndSettle();

      expect(capturedResult, isNull);
      expect(find.text('Staged Import Files'), findsOneWidget);
    });

    testWidgets('displays unsupported files (e.g. PDF, MD) directly in modal with warning and excludes from preview', (tester) async {
      final pdfFile = PickedTabularFile(
        name: 'activity.pdf',
        extension: 'pdf',
        bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]), // %PDF
      );

      StagedImportResult? capturedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  capturedResult = await showFileImportStagingModal(
                    context,
                    initialFiles: [studentFile, pdfFile],
                    importMode: 'student',
                    hasActiveSemester: true,
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Staged Import Files'), findsOneWidget);
      expect(find.text('students_import.csv'), findsNothing); // our studentFile name is bsit_3a_enrolled.csv
      expect(find.text('bsit_3a_enrolled.csv'), findsOneWidget);
      expect(find.text('activity.pdf'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.textContaining('PDF File'), findsOneWidget);
      expect(find.textContaining('Unsupported file format (.pdf)'), findsOneWidget);
      expect(find.textContaining('1 incompatible file will be skipped'), findsOneWidget);

      // Generating preview should only include valid studentFile
      await tester.tap(find.textContaining('Generate Preview Table'));
      await tester.pumpAndSettle();

      expect(capturedResult, isNotNull);
      expect(capturedResult!.files.length, 1);
      expect(capturedResult!.files.first.name, 'bsit_3a_enrolled.csv');
    });
  });
}

