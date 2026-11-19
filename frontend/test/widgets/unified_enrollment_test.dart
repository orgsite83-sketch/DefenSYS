import 'package:defensys/screens/web/admin/user_management/bulk_import/student_batch_enrollment_hub_view.dart';
import 'package:defensys/screens/web/admin/user_management/components/students_enrollment_view.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/academic/student_batch_draft_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/admin_overview_scope_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/services/network/connectivity_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/feedback/action_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/capture_preview.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';
import 'defensys_admin_shell_test.dart' show FakeNotificationsNotifier;

const _term = {
  'id': 2,
  'label': '1st Semester',
  'school_year': '2026-2027',
  'display_name': '1st Semester, A.Y. 2026-2027',
};

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _Periods extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() =>
      const AcademicPeriodState(activeSemester: _term);
  void switchTerm() => state = const AcademicPeriodState(
    activeSemester: {
      'id': 3,
      'label': '2nd Semester',
      'school_year': '2026-2027',
      'display_name': '2nd Semester, A.Y. 2026-2027',
    },
  );
}

class _Records extends StudentAcademicRecordsNotifier {
  _Records({this.pending = 0, this.enrolled = 0});
  final int pending, enrolled;

  void updateEnrollment(
    Map<String, int?> years, {
    int pending = 0,
    int semesterId = 2,
  }) {
    final rows = [
      for (final year in years.entries)
        {'year_level': year.key, 'enrolled': year.value},
    ];
    state = state.copyWith(
      counts: {
        ...state.counts,
        'year_summary': rows,
        'enrollment': {
          'semester_id': semesterId,
          'enrolled': years.values.fold<int>(
            0,
            (total, count) => total + (count ?? 0),
          ),
          'pending_continuations': pending,
          'by_year': rows,
        },
      },
    );
  }

  @override
  StudentAcademicRecordsState build() => StudentAcademicRecordsState(
    activeSemester: _term,
    counts: {
      'student_accounts': 64,
      'all': 128,
      'enrollment': {
        'semester_id': 2,
        'enrolled': enrolled,
        'pending_continuations': pending,
      },
    },
    students: const [
      {'id': 1, 'username': '3064'},
    ],
  );

  @override
  Future<void> fetchRecords({
    String? search,
    String? schoolYear,
    String? semester,
    String? successMessage,
  }) async {
    state = state.copyWith(
      isLoading: false,
      search: search,
      records: state.termContext == 'history'
          ? [
              {
                'id': 1,
                'student_id': 1,
                'student_name': 'Danica SOLIS',
                'student_username': '3064',
                'year_level': '3rd Year',
                'section': 'BSIT-3A',
                'semester_id': 1,
                'semester': '2nd Semester',
                'school_year': '2025-2026',
              },
            ]
          : [],
    );
  }
}

class _Users extends UserManagementNotifier {
  bool unifiedRequested = false;
  @override
  UserManagementState build() => const UserManagementState();
  @override
  Future<List<Map<String, dynamic>>> previewEnrollmentSections(
    List<Map<String, dynamic>> students,
    int semesterId, {
    bool unifiedEnrollment = false,
  }) async {
    unifiedRequested = unifiedEnrollment;
    return [
      for (final row in students)
        {
          'id_number': row['id_number'],
          'section': row['section'],
          'source': 'explicit',
          'blocking': false,
          'status_code': row['_test_status'] ?? 'ready',
        },
    ];
  }
}

class _Draft extends StudentBatchDraftNotifier {
  _Draft(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  StudentBatchDraftState build() =>
      StudentBatchDraftState(freshParsedStudents: rows);
}

class _Dashboard extends DashboardNotifier {
  _Dashboard() : super('admin');
  @override
  DashboardState build() => DashboardState(
    data: {
      'overview': {
        'semester_id': 2,
        'action_counts': {'userManagement': 1},
        'action_items': [
          {'id': 'enrollment:2', 'target_section': 'userManagement'},
        ],
      },
    },
  );
  void resolve() => state = DashboardState(
    data: {
      'overview': {'semester_id': 2, 'action_counts': {}, 'action_items': []},
    },
  );
}

Map<String, dynamic> _row(String id, String status) => {
  'id_number': id,
  'first_name': 'Student',
  'last_name': id,
  'year_level': '4th Year',
  'section': 'BSIT-4A',
  'role': 'student',
  '_test_status': status,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(dismissFeedbackToasts);

  Future<ProviderContainer> open(
    WidgetTester tester, {
    bool hub = false,
    bool shell = false,
    bool dark = false,
    Size size = const Size(1400, 1000),
    int pending = 0,
    int enrolled = 0,
    ValueChanged<DefensysAdminSection>? onNavigate,
    List<Map<String, dynamic>> rows = const [],
    Future<bool> Function(List<Map<String, dynamic>>, Map<String, dynamic>?)?
    confirm,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadPreviewFonts(force: true);
    final body = hub
        ? StudentBatchEnrollmentHubView(
            unifiedEnrollment: true,
            userState: const UserManagementState(),
            academicState: const AcademicPeriodState(activeSemester: _term),
            onBack: () {},
            onDownloadSample: null,
            onConfirmFreshImport: confirm ?? (_, __) async => false,
          )
        : SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: StudentsEnrollmentView(onOpenBulkImport: () {}),
            ),
          );
    await pumpDefensysWidget(
      tester,
      shell
          ? DefensysAdminShell(
              activeSection: DefensysAdminSection.userManagement,
              activeSemesterLabel: 'Active: 1st Semester · 2026-2027',
              onNavigate: onNavigate ?? (_) {},
              onLogout: () {},
              scrollContent: false,
              child: body,
            )
          : body,
      theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
      overrides: [
        ...authTestOverrides(),
        connectivityProvider.overrideWith(_Online.new),
        academicPeriodProvider.overrideWith(_Periods.new),
        studentAcademicRecordsProvider.overrideWith(
          () => _Records(pending: pending, enrolled: enrolled),
        ),
        userManagementProvider.overrideWith(_Users.new),
        studentBatchDraftProvider.overrideWith(() => _Draft(rows)),
        dashboardProvider('admin').overrideWith(_Dashboard.new),
        notificationsProvider.overrideWith2(
          (workspace) => FakeNotificationsNotifier(workspace),
        ),
      ],
    );
    return ProviderScope.containerOf(
      tester.element(
        find.byType(
          hub ? StudentBatchEnrollmentHubView : StudentsEnrollmentView,
        ),
      ),
    );
  }

  testWidgets(
    'active-semester metrics and enrollment warning survive switching to history',
    (tester) async {
      await open(tester, shell: true);
      expect(find.text('Enrolled this semester'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('64'), findsOneWidget);
      expect(find.text('Enrollment required'), findsOneWidget);
      expect(find.text('No enrollments for this semester'), findsOneWidget);
      expect(
        find.byTooltip('1 enrollment task needs attention'),
        findsOneWidget,
      );
      final banner = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DefensysActionBanner),
              matching: find.byType(Container),
            )
            .first,
      );
      final border = (banner.decoration! as BoxDecoration).border! as Border;
      expect(border.left, border.right);
      expect(border.left, border.top);
      await capturePreview(
        tester,
        find.byType(StudentsEnrollmentView),
        'enrollment-unified-desktop',
        viewport: true,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(StudentsEnrollmentView),
          matching: find.text('Active semester'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('All academic records').last);
      await tester.pumpAndSettle();
      expect(find.text('Danica SOLIS'), findsOneWidget);
      expect(find.text('Enrollment required'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty years retain one reminder after import while later workspaces stay accessible',
    (tester) async {
      DefensysAdminSection? navigated;
      final container = await open(
        tester,
        shell: true,
        enrolled: 64,
        onNavigate: (section) => navigated = section,
      );
      (container.read(studentAcademicRecordsProvider.notifier) as _Records)
          .updateEnrollment({
            '1st Year': 0,
            '2nd Year': 0,
            '3rd Year': 64,
            '4th Year': 0,
          });
      for (final scope in ['capstone', 'pit']) {
        container.read(adminOverviewScopeProvider.notifier).select(scope);
        await tester.pumpAndSettle();
        expect(
          find.text(
            'No students are enrolled in 1st Year, 2nd Year, and 4th Year this semester.',
          ),
          findsOneWidget,
        );
        expect(
          find.byTooltip('1 enrollment task needs attention'),
          findsOneWidget,
        );
        await tester.tap(find.text('Student Teams'));
        expect(navigated, DefensysAdminSection.studentTeams);
        navigated = null;
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one enrollment task is visible in both program scopes and clears on resolution',
    (tester) async {
      final container = await open(
        tester,
        shell: true,
        pending: 2,
        enrolled: 1,
      );
      expect(
        find.text('2 continuing students still need enrollment.'),
        findsOneWidget,
      );
      for (final scope in ['capstone', 'pit']) {
        container.read(adminOverviewScopeProvider.notifier).select(scope);
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('1 enrollment task needs attention'),
          findsOneWidget,
        );
      }
      (container.read(dashboardProvider('admin').notifier) as _Dashboard)
          .resolve();
      await tester.pumpAndSettle();
      expect(find.byTooltip('1 enrollment task needs attention'), findsNothing);
    },
  );

  testWidgets('enrollment warning follows empty years and pending enrollment', (
    tester,
  ) async {
    final container = await open(tester);
    final records =
        container.read(studentAcademicRecordsProvider.notifier) as _Records;
    expect(
      find.text('This semester is active. No students are enrolled yet.'),
      findsOneWidget,
    );
    final years = {'1st Year': 12, '2nd Year': 0, '3rd Year': 0, '4th Year': 0};
    records.updateEnrollment(years);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No students are enrolled in 2nd Year, 3rd Year, and 4th Year this semester.',
      ),
      findsOneWidget,
    );
    years['2nd Year'] = 8;
    records.updateEnrollment(years);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No students are enrolled in 3rd Year and 4th Year this semester.',
      ),
      findsOneWidget,
    );
    expect(find.text('Enrollment by year'), findsNothing);
    await capturePreview(
      tester,
      find.byType(StudentsEnrollmentView),
      'enrollment-warning-desktop',
      viewport: true,
    );
    await tester.tap(find.text('Active semester'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All academic records').last);
    await tester.pumpAndSettle();
    expect(find.text('Danica SOLIS'), findsOneWidget);
    expect(
      find.text(
        'No students are enrolled in 3rd Year and 4th Year this semester.',
      ),
      findsOneWidget,
    );
    years['3rd Year'] = 5;
    records.updateEnrollment(years);
    await tester.pumpAndSettle();
    expect(
      find.text('No students are enrolled in 4th Year this semester.'),
      findsOneWidget,
    );
    years['4th Year'] = 9;
    records.updateEnrollment(years, pending: 1);
    await tester.pumpAndSettle();
    expect(
      find.text('1 continuing student still needs enrollment.'),
      findsOneWidget,
    );
    records.updateEnrollment(years);
    await tester.pumpAndSettle();
    expect(find.text('Enrollment required'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing or stale year counts do not claim empty year levels', (
    tester,
  ) async {
    final container = await open(tester, enrolled: 1);
    expect(find.text('Enrollment required'), findsNothing);
    final records =
        container.read(studentAcademicRecordsProvider.notifier) as _Records;
    records.updateEnrollment({'1st Year': 1, '2nd Year': null});
    await tester.pumpAndSettle();
    expect(find.text('Enrollment required'), findsNothing);
    records.updateEnrollment({'1st Year': 0}, semesterId: 1);
    await tester.pumpAndSettle();
    expect(find.text('Enrollment required'), findsNothing);
    records.updateEnrollment({'1st Year': 1, '2nd Year': 0});
    await tester.pumpAndSettle();
    expect(find.text('Enrollment required'), findsOneWidget);
    (container.read(academicPeriodProvider.notifier) as _Periods).switchTerm();
    await tester.pumpAndSettle();
    expect(find.text('Enrollment required'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unified batch has one review and confirms new and existing students together',
    (tester) async {
      var calls = 0;
      final container = await open(
        tester,
        hub: true,
        rows: [
          _row('new', 'ready'),
          _row('existing', 'existing_student'),
          _row('enrolled', 'already_enrolled'),
        ],
        confirm: (rows, context) async {
          calls++;
          expect(rows.length, 3);
          expect(context?['unified_enrollment'], isTrue);
          expect(context?['semester_id'], 2);
          return false;
        },
      );
      expect(
        (container.read(userManagementProvider.notifier) as _Users)
            .unifiedRequested,
        isTrue,
      );
      expect(find.text('Semester rollover'), findsNothing);
      expect(find.text('Import class lists'), findsNothing);
      expect(find.text('Confirm enrollment (2)'), findsOneWidget);
      expect(find.text('1 already enrolled'), findsOneWidget);
      await tester.ensureVisible(find.text('Confirm enrollment (2)'));
      await tester.tap(find.text('Confirm enrollment (2)'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(container.read(studentBatchDraftProvider).hasFreshDraft, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'semester switch requires reviewing the new target before confirmation',
    (tester) async {
      var calls = 0;
      final container = await open(
        tester,
        hub: true,
        rows: [_row('existing', 'existing_student')],
        confirm: (_, context) async {
          calls++;
          expect(context?['semester_id'], 3);
          return false;
        },
      );
      (container.read(academicPeriodProvider.notifier) as _Periods)
          .switchTerm();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirm enrollment (1)'));
      await tester.tap(find.text('Confirm enrollment (1)'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('Confirm enrollment (1)'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      dismissFeedbackToasts();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'already enrolled students are visible without an enabled duplicate confirmation',
    (tester) async {
      await open(
        tester,
        hub: true,
        rows: [_row('enrolled', 'already_enrolled')],
      );
      final button = tester.widget<ShadButton>(
        find.byKey(const ValueKey('confirm-student-enrollment')),
      );
      expect(button.enabled, isFalse);
      expect(find.text('0 ready'), findsOneWidget);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'empty semester and mixed review fit narrow width; dark=$dark',
      (tester) async {
        await open(tester, dark: dark, size: const Size(390, 1000));
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(StudentsEnrollmentView),
          'enrollment-unified-mobile-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.pumpWidget(const SizedBox());
        await open(
          tester,
          dark: dark,
          hub: true,
          size: const Size(390, 1000),
          rows: [_row('new', 'ready'), _row('existing', 'existing_student')],
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
