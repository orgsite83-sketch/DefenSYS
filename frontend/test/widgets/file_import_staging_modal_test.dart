import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/screens/web/admin/widgets/file_import_staging_modal.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/theme/app_theme.dart';

import '../helpers/capture_preview.dart';

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

    testWidgets(
      'recognizes faculty CSV in general mode, shows 10 faculty badge and generates preview',
      (tester) async {
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
      },
    );

    testWidgets(
      'rejects student class list in general (faculty) mode as incompatible',
      (tester) async {
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
        expect(
          find.textContaining('0 ready · 1 file needs attention'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Official Class List (Student)'),
          findsOneWidget,
        );
        expect(find.textContaining('Cannot import this file'), findsOneWidget);
        await tester.ensureVisible(find.text('View details').last);
        await tester.tap(find.text('View details').last);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('This file is a Student Class List'),
          findsOneWidget,
        );
        expect(find.text('Generate Preview Table'), findsOneWidget);
      },
    );

    testWidgets(
      'recognizes official student class list in student mode, sets mode to Student Batch and shows section & year badges',
      (tester) async {
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
      },
    );

    testWidgets('rejects faculty template in student mode as incompatible', (
      tester,
    ) async {
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
      expect(find.textContaining('Cannot import this file'), findsOneWidget);
      await tester.ensureVisible(find.text('View details').last);
      await tester.tap(find.text('View details').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This file is a Faculty & Staff template'),
        findsOneWidget,
      );
    });

    testWidgets(
      'marks non-student CSVs as incompatible, excludes them from valid counts and skips them on proceed',
      (tester) async {
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
        expect(find.textContaining('1 ready'), findsOneWidget);
        expect(
          find.textContaining('Only ready files will be imported'),
          findsOneWidget,
        );
        expect(find.textContaining('Cannot import this file'), findsOneWidget);
        await tester.ensureVisible(find.text('View details').last);
        await tester.tap(find.text('View details').last);
        await tester.pumpAndSettle();
        expect(find.textContaining('defense schedule file'), findsOneWidget);

        // Confirm generate preview button only proceeds with the 1 valid file
        await tester.tap(find.text('Generate Preview Table (2 rows)'));
        await tester.pumpAndSettle();

        expect(capturedResult, isNotNull);
        expect(capturedResult!.files.length, 1);
        expect(capturedResult!.files.first.name, 'bsit_3a_enrolled.csv');
      },
    );

    testWidgets('Cancel button dismisses modal and returns null', (
      tester,
    ) async {
      StagedImportResult? capturedResult = const StagedImportResult(
        files: [],
        importMode: 'none',
      );

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

    testWidgets('Close (X) button dismisses modal and returns null', (
      tester,
    ) async {
      StagedImportResult? capturedResult = const StagedImportResult(
        files: [],
        importMode: 'none',
      );

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

    testWidgets(
      'blocks student import and disables preview button when hasActiveSemester is false',
      (tester) async {
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
        expect(
          tester
              .widget<ShadButton>(
                find.widgetWithText(ShadButton, 'Active Semester Required'),
              )
              .enabled,
          isFalse,
        );

        // Button is disabled, tapping should not dismiss modal or return result
        await tester.tap(
          find.text('Active Semester Required'),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(capturedResult, isNull);
        expect(find.text('Staged Import Files'), findsOneWidget);
      },
    );

    testWidgets(
      'displays unsupported files (e.g. PDF, MD) directly in modal with warning and excludes from preview',
      (tester) async {
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
        expect(
          find.text('students_import.csv'),
          findsNothing,
        ); // our studentFile name is bsit_3a_enrolled.csv
        expect(find.text('bsit_3a_enrolled.csv'), findsOneWidget);
        expect(find.text('activity.pdf'), findsOneWidget);
        expect(find.text('PDF'), findsOneWidget);
        expect(find.textContaining('PDF File'), findsOneWidget);
        await tester.ensureVisible(find.text('View details').last);
        await tester.tap(find.text('View details').last);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Unsupported file format (.pdf)'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Only ready files will be imported'),
          findsOneWidget,
        );

        // Generating preview should only include valid studentFile
        await tester.tap(find.textContaining('Generate Preview Table'));
        await tester.pumpAndSettle();

        expect(capturedResult, isNotNull);
        expect(capturedResult!.files.length, 1);
        expect(capturedResult!.files.first.name, 'bsit_3a_enrolled.csv');
      },
    );

    testWidgets(
      'recognizes USTP List of Enrollment by year level in student mode and generates preview',
      (tester) async {
        const byYearCsv = '''LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
,Program,Registered,Officially Enrolled,,,,,,,,
,Bachelor of Science in Information Technology,3,3,,,,,,,,
,TOTAL,,,,,,,,,,
,,3,3,,,,,,,,
LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
Bachelor of Science in Information Technology,,,,,,,,,,,
,#,Student No,Name,Program,Major,Level,,Gender,Status,Date,Date
,1,4001,"VILLAR, Marcus",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
,2,4002,"ONG, Patricia",BSIT,,4th Year,,F,Officially Enrolled,06/22/2026,06/22/2026
,3,4003,"SALAZAR, Ethan",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
''';

        final byYearFile = PickedTabularFile(
          name: 'students_4th_year_by_year_level.csv',
          extension: 'csv',
          bytes: Uint8List.fromList(byYearCsv.codeUnits),
          text: byYearCsv,
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
                      initialFiles: [byYearFile],
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
        expect(find.textContaining('Student Batch'), findsOneWidget);
        expect(
          find.textContaining('Official Class List (By Year Level)'),
          findsOneWidget,
        );
        expect(find.text('4th Year'), findsOneWidget);
        expect(find.text('3 students'), findsOneWidget);
        expect(find.text('Section: Auto-detected Section'), findsNothing);

        // Confirm generate preview button
        await tester.tap(find.text('Generate Preview Table (3 rows)'));
        await tester.pumpAndSettle();

        expect(capturedResult, isNotNull);
        expect(capturedResult!.importMode, 'student');
        expect(capturedResult!.files.length, 1);
        expect(
          capturedResult!.files.first.name,
          'students_4th_year_by_year_level.csv',
        );
      },
    );

    testWidgets(
      'rejects USTP List of Enrollment by year level in general (faculty) mode',
      (tester) async {
        const byYearCsv = '''LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
,Program,Registered,Officially Enrolled,,,,,,,,
,Bachelor of Science in Information Technology,3,3,,,,,,,,
,TOTAL,,,,,,,,,,
,,3,3,,,,,,,,
LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
Bachelor of Science in Information Technology,,,,,,,,,,,
,#,Student No,Name,Program,Major,Level,,Gender,Status,Date,Date
,1,4001,"VILLAR, Marcus",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
''';

        final byYearFile = PickedTabularFile(
          name: 'students_4th_year_by_year_level.csv',
          extension: 'csv',
          bytes: Uint8List.fromList(byYearCsv.codeUnits),
          text: byYearCsv,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    await showFileImportStagingModal(
                      context,
                      initialFiles: [byYearFile],
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
        expect(
          find.textContaining('0 ready · 1 file needs attention'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Official Class List (By Year Level)'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('View details').last);
        await tester.tap(find.text('View details').last);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'This file is a Student Class List (By Year Level)',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'blocks official class list when file academic term mismatches activeSemester',
      (tester) async {
        const byYearCsv = '''LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
,Program,Registered,Officially Enrolled,,,,,,,,
,Bachelor of Science in Information Technology,3,3,,,,,,,,
,TOTAL,,,,,,,,,,
,,3,3,,,,,,,,
LIST OF ENROLLMENT,,,,,,,,,,,
2026-2027 1st Semester,,,,,,,,,,,
Bachelor of Science in Information Technology,,,,,,,,,,,
,#,Student No,Name,Program,Major,Level,,Gender,Status,Date,Date
,1,4001,"VILLAR, Marcus",BSIT,,4th Year,,M,Officially Enrolled,06/22/2026,06/22/2026
''';

        final byYearFile = PickedTabularFile(
          name: 'students_4th_year_by_year_level.csv',
          extension: 'csv',
          bytes: Uint8List.fromList(byYearCsv.codeUnits),
          text: byYearCsv,
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
                      initialFiles: [byYearFile],
                      importMode: 'student',
                      hasActiveSemester: true,
                      activeSemester: const {
                        'school_year': '2025-2026',
                        'label': '2nd Semester',
                      },
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
        expect(find.textContaining('Academic term mismatch'), findsOneWidget);
        expect(find.textContaining('Active term:'), findsNothing);
        expect(find.textContaining('Incompatible Format'), findsNothing);
        await tester.tap(find.text('View details'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Active term: 2nd Semester, A.Y. 2025-2026'),
          findsOneWidget,
        );
        expect(find.textContaining('2026-2027'), findsWidgets);
        expect(find.text('Generate Preview Table'), findsOneWidget);

        expect(
          tester
              .widget<ShadButton>(
                find.widgetWithText(ShadButton, 'Generate Preview Table'),
              )
              .enabled,
          isFalse,
        );
        await tester.tap(
          find.text('Generate Preview Table'),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(capturedResult, isNull);

        await loadPreviewFonts();
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.devicePixelRatio = 1;
        for (final dark in [false, true]) {
          for (final width in [320.0, 390.0, 877.0, 1280.0]) {
            await tester.pumpWidget(const SizedBox.shrink());
            tester.view.physicalSize = Size(width, 640);
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(width == 320 ? 1.25 : 1),
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: FileImportStagingModal(
                    initialFiles: [byYearFile],
                    activeSemester: const {
                      'school_year': '2025-2026',
                      'label': '2nd Semester',
                    },
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.textContaining('Active term:'), findsNothing);
            final name =
                'staged-import/${dark ? 'dark' : 'light'}-${width.toInt()}';
            await capturePreview(
              tester,
              find.byType(FileImportStagingModal),
              '$name-collapsed',
              viewport: true,
            );
            await tester.ensureVisible(find.text('Academic term mismatch'));
            await tester.tap(find.text('Academic term mismatch'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              find.textContaining('Active term: 2nd Semester, A.Y. 2025-2026'),
              findsOneWidget,
            );
            expect(
              tester.getBottomRight(find.text('Generate Preview Table')).dy,
              lessThan(640),
            );
            // A small viewport scrolls the file body while keeping actions pinned.
            await tester.ensureVisible(find.textContaining('Active term:'));
            await tester.pumpAndSettle();
            expect(
              tester.getBottomRight(find.textContaining('Active term:')).dy,
              lessThan(
                tester
                    .getTopLeft(find.text('Add another class section or file'))
                    .dy,
              ),
            );
            await capturePreview(
              tester,
              find.byType(FileImportStagingModal),
              '$name-expanded',
              viewport: true,
            );
            await tester.ensureVisible(find.text('Academic term mismatch'));
            await tester.tap(find.text('Academic term mismatch'));
            await tester.pumpAndSettle();
            expect(find.textContaining('Active term:'), findsNothing);
          }
        }
      },
    );
  });
}
