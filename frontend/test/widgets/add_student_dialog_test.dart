import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/user_management/dialogs/add_student_dialog.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/admin/user_management_provider.dart';
import 'package:defensys/widgets/pickers/searchable_entity_picker.dart';

import '../helpers/pump_app.dart';

class FakeStudentAcademicRecordsNotifier extends StudentAcademicRecordsNotifier {
  final List<Map<String, dynamic>> mockRecords;

  FakeStudentAcademicRecordsNotifier({this.mockRecords = const []});

  @override
  StudentAcademicRecordsState build() {
    return StudentAcademicRecordsState(
      isLoading: false,
      records: mockRecords,
    );
  }
}

class FakeUserManagementNotifier extends UserManagementNotifier {
  @override
  UserManagementState build() {
    return const UserManagementState(
      isLoading: false,
      users: [],
      guestCodes: [],
    );
  }
}

void main() {
  final mockSchoolYears = [
    {
      'id': 1,
      'label': '2026-2027',
      'semesters': [
        {'id': 10, 'label': '1st Semester', 'school_year': '2026-2027'},
        {'id': 20, 'label': '2nd Semester', 'school_year': '2026-2027'},
      ],
    }
  ];

  final mockActiveSemester = {
    'id': 10,
    'label': '1st Semester',
    'school_year': '2026-2027',
  };

  final mockStudents = [
    {'id': 1, 'username': '3011', 'name': 'Carlos REYES', 'email': '3011@ustp.edu.ph'},
    {'id': 2, 'username': '3012', 'name': 'Maria SANTOS', 'email': '3012@ustp.edu.ph'},
    {'id': 3, 'username': '208', 'name': 'Jonathan Beltran', 'email': '208@ustp.edu.ph'},
  ];

  testWidgets('AddStudentDialog filters out already enrolled students for active semester', (tester) async {
    // Carlos (id 1) and Maria (id 2) already have records in semester 10
    final mockRecords = [
      {
        'id': 101,
        'student_id': 1,
        'student_username': '3011',
        'student_name': 'Carlos REYES',
        'semester_id': 10,
        'year_level': '3rd Year',
        'section': 'BSIT-3A',
      },
      {
        'id': 102,
        'student_id': 2,
        'student_username': '3012',
        'student_name': 'Maria SANTOS',
        'semester_id': 10,
        'year_level': '3rd Year',
        'section': 'BSIT-3A',
      },
    ];

    await pumpDefensysWidget(
      tester,
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AddStudentDialog.show(
                  context,
                  students: mockStudents,
                  schoolYears: mockSchoolYears,
                  activeSemester: mockActiveSemester,
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
      overrides: [
        studentAcademicRecordsProvider.overrideWith(
          () => FakeStudentAcademicRecordsNotifier(mockRecords: mockRecords),
        ),
        userManagementProvider.overrideWith(
          () => FakeUserManagementNotifier(),
        ),
      ],
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify Add Student Record dialog opens
    expect(find.text('Add Student Record'), findsOneWidget);
    expect(find.text('1 unenrolled student available'), findsOneWidget);
    expect(find.byType(SearchableEntityPicker<int>), findsOneWidget);

    // Open SearchableEntityPicker
    await tester.tap(find.byType(SearchableEntityPicker<int>));
    await tester.pumpAndSettle();

    // Only Jonathan Beltran (208) should be present in the dropdown list, NOT Carlos or Maria
    expect(find.text('Jonathan Beltran'), findsWidgets);
    expect(find.text('Carlos REYES'), findsNothing);
    expect(find.text('Maria SANTOS'), findsNothing);

    // Close dialog
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
  });

  testWidgets('AddStudentDialog displays notice when all students are already enrolled', (tester) async {
    // All 3 students enrolled
    final mockRecords = [
      {'id': 101, 'student_id': 1, 'semester_id': 10},
      {'id': 102, 'student_id': 2, 'semester_id': 10},
      {'id': 103, 'student_id': 3, 'semester_id': 10},
    ];

    await pumpDefensysWidget(
      tester,
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AddStudentDialog.show(
                  context,
                  students: mockStudents,
                  schoolYears: mockSchoolYears,
                  activeSemester: mockActiveSemester,
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
      overrides: [
        studentAcademicRecordsProvider.overrideWith(
          () => FakeStudentAcademicRecordsNotifier(mockRecords: mockRecords),
        ),
        userManagementProvider.overrideWith(
          () => FakeUserManagementNotifier(),
        ),
      ],
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify notice appears
    expect(
      find.text('All registered students already have an academic record for this semester.'),
      findsOneWidget,
    );
    expect(find.text('Register New Student Intake Instead'), findsOneWidget);

    // Close dialog
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
  });
}
