import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/faculty/pit_lead/pit_lead_cohort_screen.dart';
import 'package:defensys/screens/web/faculty/pit_instructor/pit_instructor_assignment_screen.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/pit_lead_cohort_provider.dart';
import 'package:defensys/services/pit_instructor_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/widgets/pit/instructor_assignment_actions.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import '../helpers/capture_preview.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/defensys_tokens.dart';

import '../helpers/pump_app.dart';

class FakePitLeadCohortNotifier extends PitLeadCohortNotifier {
  int loads = 0;
  List<Map<String, dynamic>>? responseStudents;
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
  Future<void> fetchCohort({
    String? search,
    String? teamStatusFilter,
    String? scope,
  }) async {
    loads++;
    if (responseStudents != null) {
      state = state.copyWith(students: responseStudents);
    }
  }

  List<Map<String, dynamic>> get rosterRows => state.students;
}

class FakePitInstructorNotifier extends PitInstructorNotifier {
  final restoreRequests = <(int, bool)>[];
  final replacementRequests = <(int, int)>[];
  bool statusSuccess = true;
  List<Map<String, dynamic>> get assignmentRows => state.assignments;
  int loads = 0;

  @override
  PitInstructorState build() {
    return const PitInstructorState(
      yearLevel: '1st Year',
      activeSemester: '1st Semester, A.Y. 2026-2027',
      assignments: [
        {
          'id': 1,
          'faculty_id': 10,
          'faculty_username': 'FAC-101',
          'faculty_name': 'Ricardo Fontanilla',
          'faculty_email': 'rfontanilla@defensys.edu',
          'section': 'BSIT-1A',
          'year_level': '1st Year',
          'semester_label': '1st Semester, 2026-2027',
          'is_active': true,
        },
        {
          'id': 2,
          'faculty_id': 11,
          'faculty_username': 'FAC-102',
          'faculty_name': 'Eduardo Padilla',
          'section': 'BSIT-1B',
          'year_level': '1st Year',
          'semester_label': '1st Semester, 2026-2027',
          'is_active': false,
        },
      ],
      faculty: [
        {
          'id': 10,
          'name': 'Ricardo Fontanilla',
          'username': 'rfontanilla',
          'displayRole': {'label': 'Faculty'},
        },
        {
          'id': 11,
          'name': 'Eduardo Padilla',
          'username': 'FAC-102',
          'displayRole': {'label': 'Faculty'},
        },
      ],
    );
  }

  @override
  Future<void> fetchAssignments() async {
    loads++;
  }

  @override
  Future<bool> setAssignmentActive(int assignmentId, bool isActive) async {
    restoreRequests.add((assignmentId, isActive));
    if (!statusSuccess) {
      state = state.copyWith(error: 'The assignment could not be updated.');
      return false;
    }
    state = state.copyWith(
      assignments: [
        for (final assignment in state.assignments)
          {
            ...assignment,
            if (assignment['id'] == assignmentId) 'is_active': isActive,
          },
      ],
    );
    return true;
  }

  @override
  Future<bool> replaceInstructor(int assignmentId, int facultyId) async {
    replacementRequests.add((assignmentId, facultyId));
    final source = state.assignments.firstWhere((a) => a['id'] == assignmentId);
    state = state.copyWith(
      assignments: [
        for (final a in state.assignments)
          {...a, if (a['id'] == assignmentId) 'is_active': false},
        {
          ...source,
          'id': 3,
          'faculty_id': facultyId,
          'faculty_username': 'FAC-102',
          'faculty_name': 'Eduardo Padilla',
        },
      ],
    );
    return true;
  }
}

class FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() => const AcademicPeriodState();
  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class FakeStudentAcademicRecordsNotifier
    extends StudentAcademicRecordsNotifier {
  @override
  StudentAcademicRecordsState build() => const StudentAcademicRecordsState();
  @override
  Future<void> fetchRecords({
    String? search,
    String? schoolYear,
    String? semester,
    String? successMessage,
  }) async {}
}

class FakeUserManagementNotifier extends UserManagementNotifier {
  @override
  UserManagementState build() => const UserManagementState();
  @override
  Future<void> fetchUsers({
    String? search,
    String? role,
    String? successMessage,
  }) async {}
}

Future<void> pumpInstructorTab(
  WidgetTester tester,
  FakePitInstructorNotifier notifier, {
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pitLeadCohortProvider.overrideWith(FakePitLeadCohortNotifier.new),
        pitInstructorProvider.overrideWith(() => notifier),
        academicPeriodProvider.overrideWith(FakeAcademicPeriodNotifier.new),
        studentAcademicRecordsProvider.overrideWith(
          FakeStudentAcademicRecordsNotifier.new,
        ),
        userManagementProvider.overrideWith(FakeUserManagementNotifier.new),
      ],
      child: RepaintBoundary(
        key: const ValueKey('instructor-preview'),
        child: MaterialApp(
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: PitLeadCohortScreen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Section Instructors'));
  await tester.pumpAndSettle();
}

Future<void> openInstructorMenu(WidgetTester tester, int id) async {
  await tester.tap(find.byKey(ValueKey('instructor-actions-$id')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(dismissFeedbackToasts);
  tearDown(dismissFeedbackToasts);
  setUpAll(loadPreviewFonts);
  testWidgets(
    'PitLeadCohortScreen renders User Management layout with 2 tabs and metric cards',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final instructorNotifier = FakePitInstructorNotifier();
      final cohortNotifier = FakePitLeadCohortNotifier();

      await pumpDefensysWidget(
        tester,
        const PitLeadCohortScreen(),
        overrides: [
          pitLeadCohortProvider.overrideWith(() => cohortNotifier),
          pitInstructorProvider.overrideWith(() => instructorNotifier),
          academicPeriodProvider.overrideWith(
            () => FakeAcademicPeriodNotifier(),
          ),
          studentAcademicRecordsProvider.overrideWith(
            () => FakeStudentAcademicRecordsNotifier(),
          ),
          userManagementProvider.overrideWith(
            () => FakeUserManagementNotifier(),
          ),
        ],
      );

      // Header
      expect(find.text('User Management'), findsOneWidget);
      expect(
        find.text('1st Year · 1st Semester, A.Y. 2026-2027'),
        findsOneWidget,
      );

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
      expect(
        find.text('Ricardo Fontanilla'),
        findsWidgets,
      ); // Instructor tag under section

      void expectMetric(String title, String value) {
        final metric = find
            .ancestor(of: find.text(title), matching: find.byType(Column))
            .first;
        expect(
          find.descendant(of: metric, matching: find.text(value)),
          findsOneWidget,
        );
      }

      // Simulate the searched API response while retaining full cohort counts.
      expect(cohortNotifier.loads, 1);
      final fullRoster = cohortNotifier.rosterRows;
      cohortNotifier.responseStudents = [fullRoster.first];
      await tester.enterText(find.byType(TextField).first, 'Sofia');
      await tester.pumpAndSettle();
      expectMetric('All Records', '2');
      expectMetric('Filtered', '1');
      expectMetric('Students', '2');
      expect(
        find.text('2'),
        findsNWidgets(3),
      ); // Two total cards and tab badge.
      expect(find.text('Sofia Lim'), findsOneWidget);
      expect(find.text('James Rivera'), findsNothing);

      cohortNotifier.responseStudents = [];
      await tester.enterText(find.byType(TextField).first, 'no-match');
      await tester.pumpAndSettle();
      expectMetric('All Records', '2');
      expectMetric('Filtered', '0');
      expectMetric('Students', '2');
      expect(find.text('No student records found'), findsOneWidget);

      cohortNotifier.responseStudents = fullRoster;
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expectMetric('All Records', '2');
      expectMetric('Filtered', '2');
      expectMetric('Students', '2');
      expect(find.text('James Rivera'), findsOneWidget);

      // Switch to Section Instructors tab
      final loadsBeforeTabSwitch = cohortNotifier.loads;
      expect(instructorNotifier.loads, 1);
      await tester.tap(find.text('Section Instructors'));
      await tester.pumpAndSettle();
      expect(cohortNotifier.loads, loadsBeforeTabSwitch + 1);
      expect(instructorNotifier.loads, 2);

      // Verify Tab 2 metrics and contents
      expect(find.text('Total Instructors'), findsOneWidget);
      expect(find.text('Sections Covered'), findsOneWidget);
      expect(find.text('Needs Assignment'), findsOneWidget);
      expect(find.text('Assign Section Instructor'), findsWidgets);
      expect(find.text('ID: FAC-101'), findsOneWidget);
      expect(find.text('ID: FAC-102'), findsOneWidget);
      expect(find.text('Deactivate'), findsNothing);
      expect(find.text('Restore'), findsNothing);
      expect(find.text('Change'), findsNothing);
      expect(find.byIcon(Icons.more_horiz_rounded), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('instructor-actions-1')));
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.byType(ShadContextMenuItem), findsNWidgets(3));
      expect(
        ShadTheme.of(
          tester.element(find.byKey(const ValueKey('instructor-actions-1'))),
        ).colorScheme.popover,
        DefensysTokens.surface,
      );
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Instructor details'), findsOneWidget);
      expect(find.text('rfontanilla@defensys.edu'), findsOneWidget);
      expect(find.text('FAC-101'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('instructor-actions-2')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(instructorNotifier.restoreRequests, [(2, true)]);
      expect(find.text('Restore'), findsNothing);
      expect(find.text('Deactivate'), findsNothing);
      expect(find.byType(InstructorAssignmentActions), findsNWidgets(2));
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'assignment screen offers scoped actions and Restore for inactive assignments',
    (tester) async {
      final notifier = FakePitInstructorNotifier();
      await pumpDefensysWidget(
        tester,
        const PitInstructorAssignmentScreen(),
        overrides: [pitInstructorProvider.overrideWith(() => notifier)],
      );
      expect(find.text('Deactivate'), findsNothing);
      expect(find.text('Restore'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('instructor-actions-2')),
      );
      await tester.tap(find.byKey(const ValueKey('instructor-actions-2')));
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Change'), findsNothing);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Restore'), findsOneWidget);
      await tester.ensureVisible(find.text('Restore'));
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(notifier.restoreRequests, [(2, true)]);
      expect(find.text('Restore'), findsNothing);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'remove confirms the specific assignment and cancellation preserves it',
    (tester) async {
      final notifier = FakePitInstructorNotifier();
      await pumpInstructorTab(tester, notifier);
      await openInstructorMenu(tester, 1);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('instructor-preview')),
        'pit-instructor-actions-menu',
      );
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove instructor?'), findsOneWidget);
      expect(
        find.textContaining('Remove Ricardo Fontanilla from BSIT-1A'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(notifier.restoreRequests, isEmpty);
      await openInstructorMenu(tester, 1);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(notifier.restoreRequests, [(1, false)]);
      expect(notifier.assignmentRows.first['is_active'], isFalse);
      await openInstructorMenu(tester, 1);
      expect(find.text('Restore'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(notifier.restoreRequests, [(1, false), (1, true)]);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Change prefills the instructor and replaces in one save', (
    tester,
  ) async {
    final notifier = FakePitInstructorNotifier();
    await pumpInstructorTab(tester, notifier);
    await openInstructorMenu(tester, 1);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('Change Section Instructor'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .initialValue,
      10,
    );
    final section = tester.widget<TextField>(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
    );
    expect(section.controller!.text, 'BSIT-1A');
    expect(section.readOnly, isTrue);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eduardo Padilla (Faculty)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save change'));
    await tester.pumpAndSettle();
    expect(notifier.replacementRequests, [(1, 11)]);
    expect(notifier.restoreRequests, isEmpty);
    expect(notifier.assignmentRows.first['is_active'], isFalse);
    expect(notifier.assignmentRows.last['faculty_id'], 11);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'failed removal keeps the instructor active and reports the error',
    (tester) async {
      final notifier = FakePitInstructorNotifier()..statusSuccess = false;
      await pumpInstructorTab(tester, notifier);
      await openInstructorMenu(tester, 1);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(notifier.assignmentRows.first['is_active'], isTrue);
      expect(find.text('The assignment could not be updated.'), findsWidgets);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'assignment details preserve the ID number in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        await pumpInstructorTab(
          tester,
          FakePitInstructorNotifier(),
          dark: dark,
        );
        await openInstructorMenu(tester, 1);
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
        expect(find.text('FAC-101'), findsOneWidget);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('instructor-preview')),
          'pit-instructor-details-${dark ? 'dark' : 'light'}',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'shadcn instructor menu and details fit a narrow ${dark ? 'dark' : 'light'} screen',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final notifier = FakePitInstructorNotifier();
        await pumpDefensysWidget(
          tester,
          Center(
            child: InstructorAssignmentActions(
              assignment: notifier.build().assignments.first,
              onChange: () {},
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: [pitInstructorProvider.overrideWith(() => notifier)],
        );
        await openInstructorMenu(tester, 1);
        expect(find.text('Details'), findsOneWidget);
        expect(find.text('Change'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
        expect(find.text('FAC-101'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
