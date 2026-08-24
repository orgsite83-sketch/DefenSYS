import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/user_management/user_management_screen.dart';
import 'package:defensys/screens/web/admin/user_management/bulk_import/bulk_import_view.dart';
import 'package:defensys/screens/web/admin/widgets/file_import_staging_modal.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/notifications/notifications_provider.dart';

import '../helpers/pump_app.dart';

class FakeNotificationsNotifier extends NotificationsNotifier {
  @override
  NotificationsState build() {
    return const NotificationsState(
      notifications: [],
      unreadCount: 0,
    );
  }

  @override
  Future<void> fetchNotifications() async {}
}

class FakeUserManagementNotifier extends UserManagementNotifier {
  @override
  UserManagementState build() {
    return const UserManagementState(
      isLoading: false,
      users: [
        {
          'id': 1,
          'username': 'admin',
          'email': 'admin@defensys.edu',
          'name': 'System Admin',
          'first_name': 'System',
          'last_name': 'Admin',
          'role': 'admin',
          'is_active': true,
          'is_panelist': false,
          'is_pit_lead': false,
          'is_adviser': false,
          'is_documenter': false,
        }
      ],
      guestCodes: [],
    );
  }

  @override
  Future<void> fetchUsers({String? search, String? role, String? successMessage}) async {}
}

class FakeStudentAcademicRecordsNotifier extends StudentAcademicRecordsNotifier {
  @override
  StudentAcademicRecordsState build() {
    return const StudentAcademicRecordsState(
      isLoading: false,
      records: [
        {
          'id': 101,
          'student_id': 201,
          'student_username': '2023-0001',
          'student_name': 'Juan Dela Cruz',
          'student_email': 'juan@ustp.edu.ph',
          'first_name': 'Juan',
          'last_name': 'Dela Cruz',
          'year_level': '4th Year',
          'section': 'BSIT-4A',
          'school_year': '2026-2027',
          'semester': '1st Semester',
          'is_active': true,
        },
      ],
      rolloverRows: [
        {
          'record': {
            'id': 101,
            'student_id': 201,
            'student_username': '2023-0001',
            'student_name': 'Juan Dela Cruz',
            'student_email': 'juan@ustp.edu.ph',
            'year_level': '3rd Year',
            'section': 'BSIT-3A',
          },
          'action_default': 'promote',
          'promote_result': {
            'year_level': '4th Year',
            'section': 'BSIT-4A',
          },
          'is_new_student': false,
        },
        {
          'record': {
            'id': null,
            'student_id': null,
            'student_username': '2024-0099',
            'student_name': 'New Student Maria',
            'student_email': 'maria@ustp.edu.ph',
            'year_level': '1st Year',
            'section': 'BSIT-1A',
          },
          'action_default': 'create',
          'promote_result': {
            'year_level': '1st Year',
            'section': 'BSIT-1A',
          },
          'is_new_student': true,
        },
      ],
      students: [],
      schoolYears: [],
    );
  }

  @override
  Future<void> fetchRecords({String? schoolYear, String? semester, String? yearLevel, String? search, String? successMessage}) async {}

  @override
  Future<List<Map<String, dynamic>>> fetchStudentHistory(String username) async {
    return [
      {
        'id': 101,
        'school_year': '2026-2027',
        'semester': '1st Semester',
        'year_level': '4th Year',
        'section': 'BSIT-4A',
      }
    ];
  }
}

class FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() {
    return const AcademicPeriodState();
  }

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class FakeAcademicPeriodNotifierWithActiveSemester extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() {
    return const AcademicPeriodState(
      activeSemester: {
        'id': 1,
        'label': '1st Semester',
        'school_year': '2026-2027',
        'display_name': '1st Semester, A.Y. 2026-2027',
        'is_active': true,
      },
    );
  }

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

void main() {
  testWidgets('UserManagementScreen defaults to Students & Enrollment tab', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const Scaffold(body: UserManagementScreen()),
      overrides: [
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
        userManagementProvider.overrideWith(() => FakeUserManagementNotifier()),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        studentAcademicRecordsProvider.overrideWith(() => FakeStudentAcademicRecordsNotifier()),
      ],
    );

    await tester.pumpAndSettle();

    expect(find.text('User & Team Management'), findsOneWidget);
    expect(find.text('Batch Enrollment'), findsOneWidget);
    expect(find.text('Add Single Student'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
  });

  testWidgets('UserManagementScreen renders properly with 1 user when faculty tab is selected', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const Scaffold(body: UserManagementScreen(initialUserTab: UserManagementTab.faculty)),
      overrides: [
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
        userManagementProvider.overrideWith(() => FakeUserManagementNotifier()),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        studentAcademicRecordsProvider.overrideWith(() => FakeStudentAcademicRecordsNotifier()),
      ],
    );

    await tester.pumpAndSettle();

    expect(find.text('User & Team Management'), findsOneWidget);
    expect(find.text('User ID'), findsOneWidget);
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('System Role'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);

    expect(find.text('admin'), findsWidgets);
    expect(find.text('System Admin'), findsOneWidget);
    expect(find.text('admin@defensys.edu'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);

    expect(find.byIcon(Icons.edit_square), findsOneWidget);
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.lock_reset_rounded), findsNothing);
  });

  testWidgets('UserManagementScreen opens Bulk Import Faculty view with faculty format card', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const Scaffold(body: UserManagementScreen(initialUserTab: UserManagementTab.faculty)),
      overrides: [
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
        userManagementProvider.overrideWith(() => FakeUserManagementNotifier()),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        studentAcademicRecordsProvider.overrideWith(() => FakeStudentAcademicRecordsNotifier()),
      ],
    );

    await tester.pumpAndSettle();

    expect(find.text('Bulk Import Faculty'), findsOneWidget);
    await tester.tap(find.text('Bulk Import Faculty'));
    await tester.pumpAndSettle();

    expect(find.text('Bulk Import Faculty & Staff'), findsOneWidget);
    expect(find.text('CSV Format'), findsOneWidget);
    expect(find.text('Back to Faculty'), findsOneWidget);

    await tester.tap(find.text('Back to Faculty'));
    await tester.pumpAndSettle();

    expect(find.text('User & Team Management'), findsOneWidget);
  });

  testWidgets('BulkImportView staging modal allows staging files and generating preview table', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const facultyCsv = '''id_number,first_name,last_name,email,role
FAC-101,John,Doe,jdoe@ustp.edu.ph,faculty
FAC-102,Jane,Smith,jsmith@ustp.edu.ph,faculty
''';

    final facultyFile = PickedTabularFile(
      name: 'faculty_sample.csv',
      extension: 'csv',
      bytes: Uint8List.fromList(facultyCsv.codeUnits),
      text: facultyCsv,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BulkImportView(
            state: const UserManagementState(isLoading: false, users: [], guestCodes: []),
            academicState: const AcademicPeriodState(),
            onBack: () {},
            onConfirmUpload: (users, context) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Trigger staging modal manually via showFileImportStagingModal
    final modalResultFuture = showFileImportStagingModal(
      tester.element(find.byType(BulkImportView)),
      initialFiles: [facultyFile],
      importMode: 'general',
    );
    await tester.pumpAndSettle();

    expect(find.text('Staged Import Files'), findsOneWidget);
    expect(find.text('Generate Preview Table (2 rows)'), findsOneWidget);

    // Tap Generate Preview Table
    await tester.tap(find.text('Generate Preview Table (2 rows)'));
    await tester.pumpAndSettle();

    final result = await modalResultFuture;
    expect(result, isNotNull);
    expect(result!.files.length, 1);
  });

  testWidgets('BulkImportView rejects student template and prevents staging student records as faculty', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const studentCsv = '''Subject Code,IT311
Class Section,BSIT-3A
Year Level,3rd Year
Instructor,Prof. Alan Turing

Student Number,Full Name,Email,Year Level
20230001,"SMITH, John",john.smith@ustp.edu.ph,3rd Year
20230002,"DOE, Jane",jane.doe@ustp.edu.ph,3rd Year
''';

    final studentFile = PickedTabularFile(
      name: 'students_import.csv',
      extension: 'csv',
      bytes: Uint8List.fromList(studentCsv.codeUnits),
      text: studentCsv,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BulkImportView(
            state: const UserManagementState(isLoading: false, users: [], guestCodes: []),
            academicState: const AcademicPeriodState(),
            onBack: () {},
            onConfirmUpload: (users, context) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Trigger staging modal with student file in general (faculty) mode
    showFileImportStagingModal(
      tester.element(find.byType(BulkImportView)),
      initialFiles: [studentFile],
      importMode: 'general',
    );
    await tester.pumpAndSettle();

    expect(find.text('Staged Import Files'), findsOneWidget);
    expect(find.textContaining('This file is a Student Class List'), findsOneWidget);
    expect(find.textContaining('Incompatible Format'), findsOneWidget);

    // Verify Generate Preview Table is disabled / shows 0 rows
    expect(find.text('Generate Preview Table'), findsOneWidget);
    await tester.tap(find.text('Generate Preview Table'));
    await tester.pumpAndSettle();

    // Modal stays open because button is disabled for invalid file
    expect(find.text('Staged Import Files'), findsOneWidget);
  });

  testWidgets('Students tab shows Batch Enrollment and opens student details with profile card and actions', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const Scaffold(body: UserManagementScreen(initialUserTab: UserManagementTab.students)),
      overrides: [
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
        userManagementProvider.overrideWith(() => FakeUserManagementNotifier()),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        studentAcademicRecordsProvider.overrideWith(() => FakeStudentAcademicRecordsNotifier()),
      ],
    );

    await tester.pumpAndSettle();

    // Verify Students view rendered with stats and table
    expect(find.text('Batch Enrollment'), findsOneWidget);
    expect(find.text('Add Single Student'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);

    // Open Student Details via details tooltip
    final detailsButton = find.byTooltip('Student Details');
    expect(detailsButton, findsOneWidget);
    await tester.tap(detailsButton);
    await tester.pumpAndSettle();

    // Verify Modal Elements
    expect(find.text('Student Profile & Enrollment'), findsOneWidget);
    expect(find.text('Edit Details'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    // Click Edit Details
    await tester.tap(find.text('Edit Details'));
    await tester.pumpAndSettle();

    // Verify Edit Mode
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Cancel edit mode back to view mode
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Details'), findsOneWidget);

    // Close modal
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Open Batch Enrollment
    await tester.tap(find.text('Batch Enrollment'));
    await tester.pumpAndSettle();

    // Verify Hub Elements
    expect(find.text('Batch Student Enrollment Hub'), findsOneWidget);
    expect(find.text('Fresh Student Intake (Import)'), findsOneWidget);
    expect(find.text('Semester Rollover & Promotion'), findsOneWidget);
    expect(find.text('Back to Students'), findsOneWidget);

    // Switch to Semester Rollover & Promotion mode
    await tester.tap(find.text('Semester Rollover & Promotion'));
    await tester.pumpAndSettle();

    // Click Back to Students
    await tester.tap(find.text('Back to Students'));
    await tester.pumpAndSettle();

    expect(find.text('User & Team Management'), findsOneWidget);
  });

  testWidgets('Batch Student Enrollment Hub recognizes active semester from academicPeriodProvider', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const Scaffold(body: UserManagementScreen(initialUserTab: UserManagementTab.students)),
      overrides: [
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
        userManagementProvider.overrideWith(() => FakeUserManagementNotifier()),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifierWithActiveSemester()),
        studentAcademicRecordsProvider.overrideWith(() => FakeStudentAcademicRecordsNotifier()),
      ],
    );

    await tester.pumpAndSettle();

    // Open Batch Enrollment
    await tester.tap(find.text('Batch Enrollment'));
    await tester.pumpAndSettle();

    // Verify no "Active Academic Semester Required" warning banner
    expect(find.text('Active Academic Semester Required for Student Enrollment'), findsNothing);

    // Verify Target Term in template card
    expect(find.text('Target Term: 1st Semester, A.Y. 2026-2027'), findsOneWidget);

    // Switch to Rollover mode
    await tester.tap(find.text('Semester Rollover & Promotion'));
    await tester.pumpAndSettle();

    // Verify Target Term in rollover rules card
    expect(find.text('Target Term: 1st Semester, A.Y. 2026-2027'), findsOneWidget);
  });
}
