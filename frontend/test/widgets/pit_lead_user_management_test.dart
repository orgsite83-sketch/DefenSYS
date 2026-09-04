import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/faculty/pit_lead/pit_lead_cohort_screen.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/pit_lead_cohort_provider.dart';
import 'package:defensys/services/pit_instructor_provider.dart';
import 'package:defensys/services/user_management_provider.dart';

import '../helpers/pump_app.dart';

class FakePitLeadCohortNotifier extends PitLeadCohortNotifier {
  @override
  PitLeadCohortState build() {
    return PitLeadCohortState(
      pitLeadYear: '1st Year',
      activeSemester: '1st Semester, A.Y. 2026-2027',
      students: [
        {
          'id': 101,
          'username': '2026-0001',
          'name': 'Sofia Lim',
          'email': 'sofia@defensys.edu',
          'section': 'BSIT-1A',
          'year_level': '1st Year',
          'team_status': 'on_team',
          'team_name': 'Team Apex',
          'term_label': '1st Semester, 2026-2027',
        },
        {
          'id': 102,
          'username': '2026-0002',
          'name': 'James Rivera',
          'email': 'james@defensys.edu',
          'section': 'BSIT-1A',
          'year_level': '1st Year',
          'team_status': 'unassigned',
          'term_label': '1st Semester, 2026-2027',
        },
      ],
      counts: {'all': 2, 'on_team': 1, 'unassigned': 1},
    );
  }

  @override
  Future<void> fetchCohort({String? search, String? teamStatusFilter, String? scope}) async {}
}

class FakePitInstructorNotifier extends PitInstructorNotifier {
  @override
  PitInstructorState build() {
    return const PitInstructorState(
      yearLevel: '1st Year',
      activeSemester: '1st Semester, A.Y. 2026-2027',
      assignments: [
        {
          'id': 1,
          'faculty_id': 10,
          'faculty_name': 'Ricardo Fontanilla',
          'faculty_email': 'rfontanilla@defensys.edu',
          'section': 'BSIT-1A',
          'year_level': '1st Year',
          'semester_label': '1st Semester, 2026-2027',
          'is_active': true,
        }
      ],
      faculty: [
        {
          'id': 10,
          'name': 'Ricardo Fontanilla',
          'username': 'rfontanilla',
          'displayRole': {'label': 'Faculty'},
        }
      ],
    );
  }

  @override
  Future<void> fetchAssignments() async {}
}

class FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() => const AcademicPeriodState();
  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class FakeStudentAcademicRecordsNotifier extends StudentAcademicRecordsNotifier {
  @override
  StudentAcademicRecordsState build() => const StudentAcademicRecordsState();
  @override
  Future<void> fetchRecords({String? search, String? schoolYear, String? semester, String? successMessage}) async {}
}

class FakeUserManagementNotifier extends UserManagementNotifier {
  @override
  UserManagementState build() => const UserManagementState();
  @override
  Future<void> fetchUsers({String? search, String? role, String? successMessage}) async {}
}

void main() {
  testWidgets('PitLeadCohortScreen renders User Management layout with 2 tabs and metric cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const PitLeadCohortScreen(),
      overrides: [
        pitLeadCohortProvider.overrideWith(() => FakePitLeadCohortNotifier()),
        pitInstructorProvider.overrideWith(() => FakePitInstructorNotifier()),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        studentAcademicRecordsProvider.overrideWith(() => FakeStudentAcademicRecordsNotifier()),
        userManagementProvider.overrideWith(() => FakeUserManagementNotifier()),
      ],
    );

    // Header
    expect(find.text('User Management'), findsOneWidget);
    expect(find.text('1st Year · 1st Semester, A.Y. 2026-2027'), findsOneWidget);

    // Action buttons for Students tab
    expect(find.text('Batch Enrollment'), findsOneWidget);
    expect(find.text('Rollover Preview'), findsOneWidget);
    expect(find.text('Add Single Student'), findsOneWidget);

    // Pill Tab Bar
    expect(find.text('Students & Enrollment'), findsOneWidget);
    expect(find.text('Section Instructors'), findsOneWidget);

    // 4 Metric cards on Students Tab
    expect(find.text('All Records'), findsOneWidget);
    expect(find.text('Filtered'), findsOneWidget);
    expect(find.text('Students'), findsOneWidget);
    expect(find.text('Active Term'), findsOneWidget);

    // Students table columns and data
    expect(find.text('Sofia Lim'), findsOneWidget);
    expect(find.text('2026-0001'), findsOneWidget);
    expect(find.text('James Rivera'), findsOneWidget);
    expect(find.text('2026-0002'), findsOneWidget);
    expect(find.text('BSIT-1A'), findsWidgets);
    expect(find.text('Ricardo Fontanilla'), findsWidgets); // Instructor tag under section

    // Switch to Section Instructors tab
    await tester.tap(find.text('Section Instructors'));
    await tester.pumpAndSettle();

    // Verify Tab 2 metrics and contents
    expect(find.text('Total Instructors'), findsOneWidget);
    expect(find.text('Sections Covered'), findsOneWidget);
    expect(find.text('Needs Assignment'), findsOneWidget);
    expect(find.text('Assign Section Instructor'), findsWidgets);
    expect(find.text('rfontanilla@defensys.edu'), findsOneWidget);
  });
}
