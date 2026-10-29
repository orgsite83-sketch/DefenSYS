import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/screens/web/admin/audit_compliance/audit_compliance_screen.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/system_audit_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/defense/defense_stages_provider.dart';
import 'package:defensys/services/grading/grade_center_provider.dart';
import 'package:defensys/services/admin/reports_provider.dart';

import '../helpers/pump_app.dart';

class FakeAuthNotifier extends AuthNotifier {
  final Map<String, dynamic> _user;

  FakeAuthNotifier(this._user);

  @override
  AuthState build() {
    return AuthState(isRestoring: false, user: _user, token: 'fake_jwt_token');
  }
}

class FakeSystemAuditNotifier extends SystemAuditNotifier {
  String? lastReviewReason;
  final SystemAuditState _initialState;

  FakeSystemAuditNotifier(this._initialState);

  @override
  SystemAuditState build() => _initialState;

  @override
  Future<void> fetch({int? page}) async {}

  @override
  Future<bool> updateReviewStatus(
    int logId,
    String reviewStatus, {
    String? reason,
  }) async {
    lastReviewReason = reason;
    final updatedLogs = state.logs.map((l) {
      if (l['id'] == logId) {
        return {
          ...l,
          'review_status': reviewStatus,
          'review_status_label': reviewStatus == 'reviewed'
              ? 'Reviewed'
              : 'Needs Review',
        };
      }
      return l;
    }).toList();
    state = state.copyWith(
      logs: updatedLogs,
      selectedLog: state.selectedLog?['id'] == logId
          ? {
              ...state.selectedLog!,
              'review_status': reviewStatus,
              'review_status_label': reviewStatus == 'reviewed'
                  ? 'Reviewed'
                  : 'Needs Review',
            }
          : state.selectedLog,
    );
    return true;
  }
}

class FakeAuditReportsNotifier extends ReportsNotifier {
  String? lastFormat;
  String? lastFilename;
  String? lastEndpoint;
  Map<String, String>? lastParams;

  @override
  ReportsState build() => const ReportsState();

  @override
  Future<bool> downloadReport({
    required String endpoint,
    required Map<String, String> queryParams,
    required String defaultFilename,
    String exportFormat = 'pdf',
  }) async {
    lastFormat = exportFormat;
    lastFilename = defaultFilename;
    lastEndpoint = endpoint;
    lastParams = Map.of(queryParams);
    return true;
  }
}

class FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() => const AcademicPeriodState();

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class FakeStudentTeamsNotifier extends StudentTeamsNotifier {
  @override
  StudentTeamsState build() => const StudentTeamsState();

  @override
  Future<void> fetchTeams({
    String? historyIntake,
    String? historyPhase,
    String? historyStage,
    String? workspace,
    String? search,
    String? level,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? eventName,
    bool clearYearLevel = false,
    bool clearEventName = false,
    String? successMessage,
  }) async {}
}

class FakeDefenseStagesNotifier extends DefenseStagesNotifier {
  @override
  DefenseStagesState build() => const DefenseStagesState();

  @override
  Future<void> fetchStages({String? scope,
    String? intake,
    String? phase,
    String? stage,
    String? successMessage,}) async {}
}

class FakeGradeCenterNotifier extends GradeCenterNotifier {
  @override
  GradeCenterState build() => const GradeCenterState();

  @override
  Future<void> fetchGrades({
    String? historySemester,
    String? search,
    String? level,
    String? stage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

void main() {
  test(
    'Audit defaults to Capstone for admin and assigned PIT year for lead',
    () {
      for (final user in [
        {'id': 1, 'role': 'admin'},
        {
          'id': 2,
          'role': 'faculty',
          'is_pit_lead': true,
          'pit_lead_year': '1st Year',
        },
      ]) {
        final container = ProviderContainer(
          overrides: [authProvider.overrideWith(() => FakeAuthNotifier(user))],
        );
        final state = container.read(systemAuditProvider);
        expect(state.track, user['role'] == 'admin' ? 'capstone' : 'pit');
        expect(state.yearLevel, user['role'] == 'admin' ? '' : '1st Year');
        container.dispose();
      }
    },
  );

  final mockAuditLogs = <Map<String, dynamic>>[
    {
      'id': 45,
      'actor': 1,
      'actor_name': 'Admin User',
      'action': 'repository.archive_upload',
      'category': 'repository',
      'category_label': 'Project Archive Evidence',
      'target_type': 'ArchiveEntry',
      'target_id': '45',
      'old_values': {'status': ''},
      'new_values': {
        'file_name': '3rdYear.CAP301.ProjectAlpha.1stSemester.pdf',
        'file_size': '2.4 MB',
        'status': 'Approved',
        'track': 'capstone',
        'year_level': '3rd Year',
        'replaced_existing': false,
        'team_id': '101',
      },
      'reason': 'Official capstone archive upload',
      'review_status': 'needs_review',
      'review_status_label': 'Needs Review',
      'created_at': '2026-08-30T07:38:00Z',
    },
    {
      'id': 44,
      'actor': 1,
      'actor_name': 'Admin User',
      'action': 'rubric.create',
      'category': 'grade_center',
      'category_label': 'Grade & Rubrics',
      'target_type': 'Rubric',
      'target_id': '9',
      'old_values': {},
      'new_values': {
        'name': 'Capstone Final Defense Rubric',
        'scope': 'capstone',
        'evaluation_type': 'Panelist',
        'semester': '1st Sem 2026-2027',
        'panel_weight': 50,
        'adviser_weight': 30,
        'peer_weight': 20,
      },
      'reason': 'Configured institutional evaluation criteria',
      'review_status': 'reviewed',
      'review_status_label': 'Reviewed',
      'created_at': '2026-08-30T07:37:00Z',
    },
    {
      'id': 43,
      'actor': 1,
      'actor_name': 'Admin User',
      'action': 'grade.finalize_for_archive',
      'category': 'grade_center',
      'category_label': 'Grade & Rubrics',
      'target_type': 'TeamGrade',
      'target_id': '12',
      'old_values': {'final_grade': '88.00'},
      'new_values': {
        'team_name': 'Team ByteForce',
        'stage_label': 'Final Defense',
        'final_grade': '94.50',
        'status': 'published',
      },
      'reason': 'Final panel grade approved',
      'review_status': 'needs_review',
      'review_status_label': 'Needs Review',
      'created_at': '2026-08-30T07:35:00Z',
    },
  ];

  final mockAuditState = SystemAuditState(
    isLoading: false,
    logs: mockAuditLogs,
    counts: {
      'filtered': 45,
      'needs_review': 17,
      'captured': 28,
      'reviewed': 28,
    },
    capstoneProgress: {
      'total': 45,
      'reviewed': 28,
      'pending': 17,
      'reviewed_by_admin': 28,
    },
    pitProgress: [
      {
        'year_level': '1st Year',
        'total': 0,
        'reviewed': 0,
        'pending': 0,
        'leads': [],
      },
      {
        'year_level': '2nd Year',
        'total': 0,
        'reviewed': 0,
        'pending': 0,
        'leads': [],
      },
      {
        'year_level': '3rd Year',
        'total': 0,
        'reviewed': 0,
        'pending': 0,
        'leads': [],
      },
    ],
    options: {
      'categories': [
        {'value': 'repository', 'label': 'Archive & Vault'},
        {'value': 'grade_center', 'label': 'Grade & Rubrics'},
      ],
      'review_statuses': [
        {'value': 'needs_review', 'label': 'Needs Review'},
        {'value': 'reviewed', 'label': 'Reviewed'},
      ],
      'actions': [
        'repository.archive_upload',
        'rubric.create',
        'grade.finalize_for_archive',
      ],
    },
    totalCount: 45,
    currentPage: 1,
    totalPages: 5,
    selectedLog: mockAuditLogs.first,
  );

  testWidgets('Audit quick export downloads a formatted Excel workbook', (tester,) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final reports = FakeAuditReportsNotifier();
    await pumpDefensysWidget(
      tester,
      const AuditComplianceScreen(),
      overrides: [
        authProvider.overrideWith(() => FakeAuthNotifier({'id': 1, 'role': 'admin'}),),
        systemAuditProvider.overrideWith(() => FakeSystemAuditNotifier(mockAuditState.copyWith(search: 'rubric', track: 'capstone'),
          ),),
        reportsProvider.overrideWith(() => reports),
      ],
    );
    await tester.tap(find.byTooltip('Export Options'));
    await tester.pumpAndSettle();
    expect(find.text('Export CSV'), findsNothing);
    expect(find.text('Export current view'), findsNothing);
    expect(find.text('Export PDF'), findsOneWidget);
    await tester.tap(find.text('Export Excel'));
    await tester.pumpAndSettle();
    expect(reports.lastFormat, 'xlsx');
    expect(reports.lastFilename, 'DefenSYS_Audit_Register.xlsx');
    expect(reports.lastEndpoint, 'audit-trail/');
    expect(reports.lastParams?['search'], 'rubric');
    expect(reports.lastParams?['track'], 'capstone');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'AuditComplianceScreen renders four scope cards and clean filters',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpDefensysWidget(
        tester,
        const AuditComplianceScreen(),
        overrides: [
          authProvider.overrideWith(
            () => FakeAuthNotifier({
              'id': 1,
              'username': 'admin',
              'role': 'admin',
              'is_superuser': true,
            }),
          ),
          systemAuditProvider.overrideWith(
            () => FakeSystemAuditNotifier(mockAuditState),
          ),
          academicPeriodProvider.overrideWith(
            () => FakeAcademicPeriodNotifier(),
          ),
          studentTeamsProvider.overrideWith(() => FakeStudentTeamsNotifier()),
          defenseStagesProvider.overrideWith(() => FakeDefenseStagesNotifier()),
          gradeCenterProvider.overrideWith(() => FakeGradeCenterNotifier()),
        ],
      );

      // 1. Executive Tab Bar
      expect(find.text('Audit Trail'), findsWidgets);
      expect(find.text('Report Center'), findsOneWidget);
      expect(find.text('Live Logs'), findsOneWidget);
      expect(find.text('PDF Center'), findsOneWidget);

      // 2. Capstone and the three PIT years have their own progress cards.
      expect(find.text('Review coverage'), findsOneWidget);
      expect(find.text('28 of 45 reviewed'), findsOneWidget);
      expect(find.text('17 awaiting review'), findsOneWidget);
      expect(find.text('PIT · 1st Year'), findsOneWidget);
      expect(find.text('PIT · 2nd Year'), findsOneWidget);
      expect(find.text('PIT · 3rd Year'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Total Events'), findsNothing);
      expect(find.text('Needs Review'), findsWidgets);
      expect(find.text('Reviewed'), findsWidgets);

      // 3. Search & Filter Toolbar
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('All Process Areas'), findsOneWidget);
      expect(find.text('All Actions'), findsOneWidget);
      expect(find.text('Date Range'), findsOneWidget);
      expect(find.text('More Filters'), findsOneWidget);
      expect(find.text('Capstone'), findsWidgets);
      expect(find.text('Active'), findsNothing);
      final searchField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(searchField.decoration?.filled, isFalse);

      // 4. Status Tabs
      expect(find.text('All Events'), findsOneWidget);

      // 5. Master Table Columns (Original Layout)
      expect(find.text('DATE / TIME'), findsOneWidget);
      expect(find.text('PROCESS AREA'), findsOneWidget);
      expect(find.text('CONTROL ACTIVITY'), findsOneWidget);
      expect(find.text('RESPONSIBLE USER'), findsOneWidget);
      expect(find.text('REVIEW STATUS'), findsOneWidget);

      // 6. Master-Detail Inspector Panel
      expect(find.text('Event Details'), findsOneWidget);
      expect(find.text('Actor'), findsOneWidget);
      expect(find.text('Date & Time'), findsOneWidget);
      expect(find.text('Process Area'), findsOneWidget);
      expect(find.text('Target Resource'), findsOneWidget);
      expect(find.text('Mark as reviewed'), findsWidgets);

      final register = tester.widget<DataTable>(find.byType(DataTable).first);
      expect(register.rows.first.selected, isTrue);
      expect(
        register.rows.first.color?.resolve({WidgetState.selected}),
        const Color(0xFFF4F4F5),
      );
      await tester.tap(find.text('Rubric created').first);
      await tester.pumpAndSettle();
      final updatedRegister = tester.widget<DataTable>(
        find.byType(DataTable).first,
      );
      expect(updatedRegister.rows.first.selected, isFalse);
      expect(updatedRegister.rows[1].selected, isTrue);
    },
  );

  testWidgets('More Filters still opens System and All activity scopes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final notifier = FakeSystemAuditNotifier(mockAuditState);
    await pumpDefensysWidget(
      tester,
      const AuditComplianceScreen(),
      overrides: [
        authProvider.overrideWith(
          () => FakeAuthNotifier({'id': 1, 'role': 'admin'}),
        ),
        systemAuditProvider.overrideWith(() => notifier),
      ],
    );
    await tester.tap(find.text('More Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System & other activity'));
    await tester.tap(find.text('Apply Filter'));
    await tester.pumpAndSettle();
    expect(notifier.state.track, 'system');
    expect(find.text('System'), findsOneWidget);

    await tester.tap(find.text('More Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All activity'));
    await tester.tap(find.text('Apply Filter'));
    await tester.pumpAndSettle();
    expect(notifier.state.track, '');
    expect(find.text('All activity'), findsOneWidget);
  });

  testWidgets('AuditComplianceScreen opens and tests raw JSON modal dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const AuditComplianceScreen(),
      overrides: [
        authProvider.overrideWith(
          () => FakeAuthNotifier({
            'id': 1,
            'username': 'admin',
            'role': 'admin',
            'is_superuser': true,
          }),
        ),
        systemAuditProvider.overrideWith(
          () => FakeSystemAuditNotifier(mockAuditState),
        ),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        studentTeamsProvider.overrideWith(() => FakeStudentTeamsNotifier()),
        defenseStagesProvider.overrideWith(() => FakeDefenseStagesNotifier()),
        gradeCenterProvider.overrideWith(() => FakeGradeCenterNotifier()),
      ],
    );

    // Open "More options" popup menu
    final moreOptionsBtn = find.byTooltip('More options');
    expect(moreOptionsBtn, findsOneWidget);
    await tester.ensureVisible(moreOptionsBtn);
    await tester.tap(moreOptionsBtn);
    await tester.pumpAndSettle();

    // Click "View Raw JSON" menu item
    final viewJsonItem = find.text('View Raw JSON');
    expect(viewJsonItem, findsOneWidget);
    await tester.tap(viewJsonItem);
    await tester.pumpAndSettle();

    expect(find.text('Raw Audit Log Payload'), findsOneWidget);
    expect(find.text('Copy JSON'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    // Dismiss modal
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'AuditComplianceScreen displays diff and status correctly across create, update, and delete',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final rubricCreateLog = mockAuditLogs[1]; // rubric.create
      final rubricDeleteLog = {
        'id': 99,
        'actor': 1,
        'actor_name': 'Admin User',
        'action': 'rubric.delete',
        'category': 'grade_center',
        'category_label': 'Grade & Rubrics',
        'target_type': 'Rubric',
        'target_id': '9',
        'old_values': {'name': 'Deleted Proposal Rubric'},
        'new_values': {'deleted': true},
        'reason': 'Deprecated criteria',
        'review_status': 'needs_review',
        'review_status_label': 'Needs Review',
        'created_at': '2026-08-30T08:00:00Z',
      };

      final rubricAuditState = mockAuditState.copyWith(
        logs: [rubricCreateLog, rubricDeleteLog],
        selectedLog: rubricCreateLog,
      );

      await pumpDefensysWidget(
        tester,
        const AuditComplianceScreen(),
        overrides: [
          authProvider.overrideWith(
            () => FakeAuthNotifier({
              'id': 1,
              'username': 'admin',
              'role': 'admin',
              'is_superuser': true,
            }),
          ),
          systemAuditProvider.overrideWith(
            () => FakeSystemAuditNotifier(rubricAuditState),
          ),
          academicPeriodProvider.overrideWith(
            () => FakeAcademicPeriodNotifier(),
          ),
          studentTeamsProvider.overrideWith(() => FakeStudentTeamsNotifier()),
          defenseStagesProvider.overrideWith(() => FakeDefenseStagesNotifier()),
          gradeCenterProvider.overrideWith(() => FakeGradeCenterNotifier()),
        ],
      );

      // When rubric.create is selected:
      expect(find.text('Rubric created'), findsWidgets);
      expect(find.text('Resource Details'), findsOneWidget);

      // Verify "Open Rubric" is present in More options menu
      final moreOptionsBtn = find.byTooltip('More options');
      await tester.tap(moreOptionsBtn);
      await tester.pumpAndSettle();
      expect(find.text('Open Rubric'), findsOneWidget);

      // Dismiss menu by tapping outside
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Now select the rubric.delete entry in the table
      await tester.tap(find.text('Rubric deleted').first);
      await tester.pumpAndSettle();

      expect(find.text('This resource has been deleted'), findsOneWidget);
      expect(find.text('Last Known State'), findsOneWidget);
    },
  );

  testWidgets('Admin sees PIT review attribution and year progress', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final reviewedLog = {
      ...mockAuditLogs.first,
      'review_status': 'reviewed',
      'reviewed_by_name': 'Ricardo Fontanilla',
      'reviewed_by_role': 'pit_lead',
      'reviewed_by_year': '1st Year',
      'reviewed_at': '2026-10-11T04:42:00Z',
      'review_history': [
        {
          'to_status': 'reviewed',
          'reviewer_name': 'Ricardo Fontanilla',
          'reviewer_role': 'pit_lead',
          'reviewer_year': '1st Year',
          'created_at': '2026-10-11T04:42:00Z',
          'reason': 'Evidence checked.',
        },
      ],
    };
    final notifier = FakeSystemAuditNotifier(
      mockAuditState.copyWith(
        track: 'capstone',
        logs: [reviewedLog],
        selectedLog: reviewedLog,
        pitProgress: [
          {
            'year_level': '1st Year',
            'total': 5,
            'reviewed': 3,
            'pending': 2,
            'reviewed_by_lead': 3,
            'overdue': 1,
            'overdue_days': 7,
            'leads': [
              {'name': 'Ricardo Fontanilla'},
            ],
            'last_reviewed_by': 'Ricardo Fontanilla',
            'last_reviewed_role': 'pit_lead',
            'last_reviewed_at': '2026-10-11T04:42:00Z',
          },
        ],
      ),
    );
    await pumpDefensysWidget(
      tester,
      const AuditComplianceScreen(),
      overrides: [
        authProvider.overrideWith(
          () => FakeAuthNotifier({'id': 1, 'role': 'admin'}),
        ),
        systemAuditProvider.overrideWith(() => notifier),
      ],
    );
    expect(find.text('3 of 5 reviewed'), findsOneWidget);
    expect(find.text('2 awaiting review'), findsOneWidget);
    expect(find.text('Ricardo Fontanilla · 3 lead reviews'), findsOneWidget);
    expect(find.text('Reviewed by'), findsOneWidget);
    expect(
      find.text('Ricardo Fontanilla · PIT Lead · 1st Year'),
      findsOneWidget,
    );
    expect(find.text('Reviewed by Ricardo Fontanilla'), findsOneWidget);
    expect(find.text('Evidence checked.'), findsOneWidget);
    await tester.tap(find.text('PIT · 1st Year'));
    await tester.pumpAndSettle();
    expect(notifier.state.track, 'pit');
    expect(notifier.state.yearLevel, '1st Year');
  });

  testWidgets('Empty PIT oversight still names assigned leads', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final state = mockAuditState.copyWith(
      track: 'pit',
      pitProgress: [
        {
          'year_level': '1st Year',
          'total': 0,
          'reviewed': 0,
          'pending': 0,
          'leads': [
            {'name': 'Ricardo Fontanilla'},
          ],
        },
      ],
    );
    await pumpDefensysWidget(
      tester,
      const AuditComplianceScreen(),
      overrides: [
        authProvider.overrideWith(
          () => FakeAuthNotifier({'id': 1, 'role': 'admin'}),
        ),
        systemAuditProvider.overrideWith(() => FakeSystemAuditNotifier(state)),
      ],
    );
    expect(find.text('No events in this range'), findsOneWidget);
    expect(find.text('Ricardo Fontanilla'), findsOneWidget);
    expect(find.text('No recorded events'), findsNothing);
  });

  testWidgets('Reopen review requires and submits a reason', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final reviewedLog = {...mockAuditLogs.first, 'review_status': 'reviewed'};
    final notifier = FakeSystemAuditNotifier(
      mockAuditState.copyWith(logs: [reviewedLog], selectedLog: reviewedLog),
    );
    await pumpDefensysWidget(
      tester,
      const AuditComplianceScreen(),
      overrides: [
        authProvider.overrideWith(
          () => FakeAuthNotifier({'id': 1, 'role': 'admin'}),
        ),
        systemAuditProvider.overrideWith(() => notifier),
      ],
    );
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Reopen review'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reopen review'));
    await tester.pumpAndSettle();
    final submit = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Reopen review'),
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Enter a reason to reopen this review.'), findsOneWidget);
    expect(notifier.state.logs.first['review_status'], 'reviewed');
    await tester.enterText(
      find.byType(TextFormField),
      'Missing supporting evidence.',
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(notifier.lastReviewReason, 'Missing supporting evidence.');
    expect(notifier.state.logs.first['review_status'], 'needs_review');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('PIT Lead sees assigned year and cannot switch to Capstone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await pumpDefensysWidget(
      tester,
      const AuditComplianceScreen(),
      overrides: [
        authProvider.overrideWith(
          () => FakeAuthNotifier({
            'id': 2,
            'role': 'faculty',
            'is_pit_lead': true,
            'pit_lead_year': '1st Year',
          }),
        ),
        systemAuditProvider.overrideWith(
          () => FakeSystemAuditNotifier(
            mockAuditState.copyWith(track: 'pit', yearLevel: '1st Year'),
          ),
        ),
      ],
    );
    expect(find.text('PIT · 1st Year'), findsWidgets);
    expect(find.text('PIT review oversight'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(find.text('More Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Capstone Only'), findsNothing);
    expect(
      find.text(
        'PIT · 1st Year\nYour audit access is limited to your assigned year.',
      ),
      findsOneWidget,
    );
  });
}
