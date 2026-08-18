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

    testWidgets('auto-detects faculty CSV, sets mode to Faculty / General Users and shows 10 faculty badge', (tester) async {
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
      expect(find.text('Faculty / General Users'), findsWidgets);
      expect(find.textContaining('Faculty Accounts CSV'), findsOneWidget);
      expect(find.textContaining('10 faculty'), findsOneWidget);
      expect(find.text('Role: Faculty'), findsOneWidget);
      expect(find.text('Add another user file'), findsOneWidget);

      // Confirm generate preview button
      await tester.tap(find.text('Generate Preview Table (10 rows)'));
      await tester.pumpAndSettle();

      expect(capturedResult, isNotNull);
      expect(capturedResult!.importMode, 'general');
      expect(capturedResult!.files.length, 1);
    });

    testWidgets('allows manual switching of import mode tabs', (tester) async {
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

      // Switch mode to Student Batch
      await tester.tap(find.text('Student Batch').first);
      await tester.pumpAndSettle();

      expect(find.text('Add another class section or file'), findsOneWidget);
    });
  });
}
