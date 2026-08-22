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

void main() {
  testWidgets('UserManagementScreen renders properly with 1 user and original table design', (tester) async {
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
      const Scaffold(body: UserManagementScreen()),
      overrides: [
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
        userManagementProvider.overrideWith(() => FakeUserManagementNotifier()),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        studentAcademicRecordsProvider.overrideWith(() => FakeStudentAcademicRecordsNotifier()),
      ],
    );

    await tester.pumpAndSettle();

    // Click on Bulk Import Faculty button in header
    final bulkImportButton = find.text('Bulk Import Faculty');
    expect(bulkImportButton, findsOneWidget);
    await tester.tap(bulkImportButton);
    await tester.pumpAndSettle();

    // Verify Bulk Import View elements for Faculty
    expect(find.text('Bulk Import Faculty & Staff'), findsOneWidget);
    expect(find.text('CSV Format'), findsOneWidget);
    expect(find.text('Download Sample Template'), findsOneWidget);
    expect(find.text('Upload CSV'), findsOneWidget);
    expect(find.text('Preflight Faculty Intake Review'), findsOneWidget);
    expect(find.text('Click to Stage Faculty Spreadsheets'), findsOneWidget);
    expect(find.text('Back to Faculty'), findsOneWidget);

    // Click Back to Faculty
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

    // Trigger staging modal manually or via showFileImportStagingModal
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

    // Header actions on Students tab
    expect(find.text('Batch Enrollment'), findsOneWidget);
    expect(find.text('Add Single Student'), findsOneWidget);

    // Verify student row
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('2023-0001'), findsOneWidget);

    // Click on Student Details icon button
    final detailsButton = find.byTooltip('Student Details');
    expect(detailsButton, findsOneWidget);
    await tester.tap(detailsButton);
    await tester.pumpAndSettle();

    // Verify Student Profile & Enrollment dialog
    expect(find.text('Student Profile & Enrollment'), findsOneWidget);
    expect(find.text('Edit Details'), findsOneWidget);
    expect(find.text('Personal Profile'), findsOneWidget);
    expect(find.text('Academic Standing'), findsOneWidget);
    expect(find.text('ENROLLMENT HISTORY'), findsOneWidget);

    // Toggle in-place edit mode
    await tester.tap(find.text('Edit Details'));
    await tester.pumpAndSettle();
    expect(find.text('Editing Student Profile & Academic Record'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Cancel edit mode back to view mode
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Personal Profile'), findsOneWidget);

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

    // Verify Fresh Intake View is active by default with zero-fillup 2-column layout
    expect(find.text('Official Class List Template'), findsOneWidget);
    expect(find.text('Upload Class List Files'), findsOneWidget);
    expect(find.text('Preflight Student Intake Review'), findsOneWidget);
    expect(find.text('Download Sample Template'), findsOneWidget);

    // Switch to Semester Rollover & Promotion mode
    await tester.tap(find.text('Semester Rollover & Promotion'));
    await tester.pumpAndSettle();

    // Verify Rollover View Elements
    expect(find.text('Semester Rollover & Transition Rules'), findsOneWidget);
    expect(find.text('Cohort Source & Class List Matching'), findsOneWidget);
    expect(find.text('Preflight Cohort Review'), findsOneWidget);
    expect(find.text('Promote All'), findsOneWidget);
    expect(find.text('Retain All'), findsOneWidget);
    expect(find.text('Confirm Semester Rollover'), findsOneWidget);

    // Verify table items render correctly including create and promote rows
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('New Student Maria'), findsOneWidget);
    expect(find.text('Create & Enroll'), findsOneWidget);
    expect(find.text('Promote'), findsOneWidget);

    // Click Back to Students
    await tester.tap(find.text('Back to Students'));
    await tester.pumpAndSettle();

    expect(find.text('User & Team Management'), findsOneWidget);
  });
}
